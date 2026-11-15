//////////////////////////////////////////////////////////////////////
// uart_env_cfg: configuración de la prueba y lectura de plusargs   //
//////////////////////////////////////////////////////////////////////
// Es el único lugar donde se leen plusargs (regla 1 de la sección
// 4.2 del enunciado). parse_plusargs() pasa cada +UART_<BLOQUE>_<KNOB>
// al knob del objeto que le toca y print_knobs() imprime todo con su
// origen, para poder reproducir cualquier corrida.
// Mismo patrón que spi_env_cfg del laboratorio de SPI.
//////////////////////////////////////////////////////////////////////
class uart_env_cfg extends uvm_object;
  `uvm_object_utils(uart_env_cfg)

  // objetos que cuelgan de este (la prueba los publica por separado)
  uart_line_cfg      line;
  uart_ctrl_cfg      ctrl;
  wb_agent_cfg       wb;
  uart_ser_agent_cfg ser;
  modem_agent_cfg    mdm;
  uart_scb_cfg       scb;
  uart_cov_cfg       cov;

  // ---------------- knobs de la secuencia principal ----------------
  int unsigned ep_min        = 5;
  int unsigned ep_max        = 5;
  int unsigned ep_timeout_tc = 2000;

  // software que atiende al UART
  int unsigned sw_mode_w[]      = '{1, 1};          // interrupciones, sondeo
  int unsigned sw_delay_min     = 0;                // Tc
  int unsigned sw_delay_max     = 24;               // Tc
  int unsigned sw_delay_w[]     = '{70, 22, 8};     // 0-1, 2-6, 7-max Tc
  int unsigned sw_poll_max      = 4;                // Tc
  int unsigned sw_partial_pct   = 20;
  int unsigned sw_lsr_first_pct = 80;

  // transmisión
  int unsigned tx_bursts_max   = 6;
  int unsigned tx_len_max      = 20;
  int unsigned tx_len_w[]      = '{70, 15, 15};    // 1-15, 16, 17-max
  int unsigned tx_blind_pct    = 30;
  int unsigned tx_gap_max      = 4;                 // Tc
  int unsigned tx_break_pct    = 5;
  int unsigned tx_break_max    = 4;                 // Tc
  int unsigned data_corner_pct = 20;

  // accesos a registros y eventos raros
  int unsigned reg_noise_pct    = 10;
  int unsigned reg_dlab_pct     = 20;
  int unsigned reconfig_pct     = 10;
  int unsigned fifo_clr_mid_pct = 10;
  bit          hw_reset_chk     = 1;

  // reset asíncrono en medio del episodio
  int unsigned rst_pct       = 5;
  int unsigned rst_width_max = 5;

  // filas de la tabla que imprime print_knobs()
  string knob_rows[$];

  function new(string name = "uart_env_cfg");
    super.new(name);
    line = uart_line_cfg::type_id::create("line");
    ctrl = uart_ctrl_cfg::type_id::create("ctrl");
    wb   = wb_agent_cfg::type_id::create("wb");
    ser  = uart_ser_agent_cfg::type_id::create("ser");
    mdm  = modem_agent_cfg::type_id::create("mdm");
    scb  = uart_scb_cfg::type_id::create("scb");
    cov  = uart_cov_cfg::type_id::create("cov");
    // todos ven el mismo formato vigente
    ser.line = line;
    scb.line = line;  scb.ctrl = ctrl;
    cov.line = line;  cov.ctrl = ctrl;
  endfunction

  // -------------------------------------------------------- utilidades
  local function bit get_str(string name, output string val);
    uvm_cmdline_processor clp = uvm_cmdline_processor::get_inst();
    return clp.get_arg_value({"+", name, "="}, val) != 0;
  endfunction

  // VCS limita el ancho de campo de $sformatf, así que rellenamos a mano
  local function string pad(string s, int unsigned w);
    while (s.len() < w) s = {s, " "};
    return s;
  endfunction

  local function void add_row(string name, string val, bit found);
    knob_rows.push_back({"  +", pad(name, 26), " = ", pad(val, 16), found ? "plusarg" : "defecto"});
  endfunction

  local function void knob_int(string name, ref int unsigned v);
    string s;
    bit    found = get_str(name, s);
    if (found) v = s.atoi();
    add_row(name, $sformatf("%0d", v), found);
  endfunction

  local function void knob_bit(string name, ref bit v);
    int unsigned t = v;
    knob_int(name, t);
    v = (t != 0);
  endfunction

  // lista "a,b,c"; la cantidad de valores tiene que coincidir
  local function void knob_list(string name, ref int unsigned v[]);
    string s, tok, shown;
    bit    found = get_str(name, s);
    if (found) begin
      int idx = 0;
      tok = "";
      for (int i = 0; i <= s.len(); i++) begin
        if (i == s.len() || s[i] == ",") begin
          if (idx < v.size()) v[idx] = tok.atoi();
          idx++;
          tok = "";
        end else begin
          tok = {tok, s.substr(i, i)};
        end
      end
      if (idx != v.size())
        `uvm_fatal("KNOB", $sformatf("+%s necesita %0d valores separados por comas, recibió %0d",
                                     name, v.size(), idx))
    end
    shown = "";
    foreach (v[i]) shown = {shown, (i == 0) ? "" : ",", $sformatf("%0d", v[i])};
    add_row(name, shown, found);
  endfunction

  local function void check_weights(string name, int unsigned v[]);
    int unsigned tot = 0;
    foreach (v[i]) tot += v[i];
    if (tot == 0) `uvm_fatal("KNOB", $sformatf("+%s: todos los pesos son 0", name))
  endfunction

  local function void check_pct(string name, int unsigned v);
    if (v > 100) `uvm_fatal("KNOB", $sformatf("+%s=%0d: tiene que estar entre 0 y 100", name, v))
  endfunction

  local function void check_range(string lo_name, int unsigned lo, string hi_name, int unsigned hi);
    if (lo > hi) `uvm_fatal("KNOB", $sformatf("+%s=%0d es mayor que +%s=%0d", lo_name, lo, hi_name, hi))
  endfunction

  // +UART_SCB_EN=all o una lista como tx,rx,lsr
  local function void knob_scb_en(string name);
    string s;
    bit    found = get_str(name, s);
    if (found && s != "all") begin
      string tok = "";
      {scb.chk_tx, scb.chk_rx, scb.chk_lsr, scb.chk_iir, scb.chk_msr, scb.chk_int} = '0;
      for (int i = 0; i <= s.len(); i++) begin
        if (i == s.len() || s[i] == ",") begin
          case (tok)
            "tx":  scb.chk_tx  = 1;
            "rx":  scb.chk_rx  = 1;
            "lsr": scb.chk_lsr = 1;
            "iir": scb.chk_iir = 1;
            "msr": scb.chk_msr = 1;
            "int": scb.chk_int = 1;
            default: `uvm_fatal("KNOB", $sformatf("+%s: chequeo desconocido '%s'", name, tok))
          endcase
          tok = "";
        end else begin
          tok = {tok, s.substr(i, i)};
        end
      end
    end
    add_row(name, found ? s : "all", found);
  endfunction

  local function void knob_sev(string name);
    string s;
    bit    found = get_str(name, s);
    if (found) begin
      case (s)
        "warning": scb.dut_bug_sev = UVM_WARNING;
        "error":   scb.dut_bug_sev = UVM_ERROR;
        default:   `uvm_fatal("KNOB", $sformatf("+%s=%s: use warning o error", name, s))
      endcase
    end
    add_row(name, (scb.dut_bug_sev == UVM_ERROR) ? "error" : "warning", found);
  endfunction

  // ------------------------------------------------ único punto de lectura
  function void parse_plusargs();
    knob_rows.delete();

    // secuencia principal
    knob_int("UART_SEQ_EP_MIN",        ep_min);
    knob_int("UART_SEQ_EP_MAX",        ep_max);
    knob_int("UART_SEQ_EP_TIMEOUT",    ep_timeout_tc);

    // formato de línea y divisor
    knob_list("UART_LCR_WLS_W",        line.wls_w);   check_weights("UART_LCR_WLS_W", line.wls_w);
    knob_list("UART_LCR_STB_W",        line.stb_w);   check_weights("UART_LCR_STB_W", line.stb_w);
    knob_list("UART_LCR_PAR_W",        line.par_w);   check_weights("UART_LCR_PAR_W", line.par_w);
    knob_int("UART_DL_ZERO_PCT",       line.dl_zero_pct);
    knob_int("UART_DL_MAX_FAST",       line.dl_max_fast);
    knob_int("UART_DL_MAX",            line.dl_max);
    knob_list("UART_DL_TAIL_W",        line.dl_tail_w);
    knob_int("UART_DL_LSB_FIRST_PCT",  line.dl_lsb_first_pct);

    // FIFO, interrupciones y módem
    knob_list("UART_FCR_TL_W",         ctrl.tl_w);    check_weights("UART_FCR_TL_W", ctrl.tl_w);
    knob_int("UART_FCR_CLR_PCT",       ctrl.fcr_clr_pct);
    knob_list("UART_IER_BIT_PCT",      ctrl.ier_bit_pct);
    knob_int("UART_MCR_OUT_PCT",       ctrl.mcr_out_pct);
    knob_int("UART_MCR_LOOP_PCT",      ctrl.mcr_loop_pct);

    // software
    knob_list("UART_SW_MODE_W",        sw_mode_w);    check_weights("UART_SW_MODE_W", sw_mode_w);
    knob_int("UART_SW_DELAY_MIN",      sw_delay_min);
    knob_int("UART_SW_DELAY_MAX",      sw_delay_max);
    knob_list("UART_SW_DELAY_W",       sw_delay_w);   check_weights("UART_SW_DELAY_W", sw_delay_w);
    knob_int("UART_SW_POLL_MAX",       sw_poll_max);
    knob_int("UART_SW_PARTIAL_PCT",    sw_partial_pct);
    knob_int("UART_SW_LSR_FIRST_PCT",  sw_lsr_first_pct);

    // transmisión
    knob_int("UART_TX_BURSTS_MAX",     tx_bursts_max);
    knob_int("UART_TX_LEN_MAX",        tx_len_max);
    knob_list("UART_TX_LEN_W",         tx_len_w);     check_weights("UART_TX_LEN_W", tx_len_w);
    knob_int("UART_TX_BLIND_PCT",      tx_blind_pct);
    knob_int("UART_TX_GAP_MAX",        tx_gap_max);
    knob_int("UART_TX_BREAK_PCT",      tx_break_pct);
    knob_int("UART_TX_BREAK_MAX",      tx_break_max);
    knob_int("UART_DATA_CORNER_PCT",   data_corner_pct);

    // agente serie (recepción)
    knob_int("UART_SER_RX_CHARS_MAX",    ser.rx_chars_max);
    knob_int("UART_SER_SLOW_DL",         ser.slow_dl);
    knob_int("UART_SER_SLOW_CHARS_MAX",  ser.slow_chars_max);
    knob_int("UART_SER_RX_GAP_MAX",      ser.rx_gap_max);
    knob_list("UART_SER_RX_GAP_W",       ser.rx_gap_w);  check_weights("UART_SER_RX_GAP_W", ser.rx_gap_w);
    knob_int("UART_SER_PARITY_ERR_PCT",  ser.parity_err_pct);
    knob_int("UART_SER_FRAME_ERR_PCT",   ser.frame_err_pct);
    knob_int("UART_SER_BREAK_PCT",       ser.break_pct);
    knob_int("UART_SER_BREAK_EXTRA_MAX", ser.break_extra_max);
    knob_int("UART_SER_GLITCH_PCT",      ser.glitch_pct);
    knob_int("UART_SER_GLITCH_W_MAX",    ser.glitch_w_max);
    knob_int("UART_SER_BAUD_IN_PCT",     ser.baud_in_pct);
    knob_int("UART_SER_BAUD_IN_MAX",     ser.baud_in_max);
    knob_int("UART_SER_BAUD_OUT_PCT",    ser.baud_out_pct);
    knob_int("UART_SER_BAUD_OUT_MIN",    ser.baud_out_min);
    knob_int("UART_SER_BAUD_OUT_MAX",    ser.baud_out_max);
    knob_int("UART_SER_SHORT_STOP_PCT",  ser.short_stop_pct);

    // módem
    knob_int("UART_MDM_CHANGES_MAX",   mdm.changes_max);
    knob_list("UART_MDM_SIG_W",        mdm.sig_w);    check_weights("UART_MDM_SIG_W", mdm.sig_w);
    knob_int("UART_MDM_GAP_MAX",       mdm.gap_max);
    knob_int("UART_MDM_MULTI_PCT",     mdm.multi_pct);

    // registros y eventos raros
    knob_int("UART_REG_NOISE_PCT",     reg_noise_pct);
    knob_int("UART_REG_DLAB_PCT",      reg_dlab_pct);
    knob_int("UART_REG_RECONFIG_PCT",  reconfig_pct);
    knob_int("UART_REG_FIFO_CLR_PCT",  fifo_clr_mid_pct);
    knob_bit("UART_REG_HW_RESET_CHK",  hw_reset_chk);

    // bus Wishbone
    knob_int("UART_WB_GAP_MAX",        wb.gap_max);
    knob_int("UART_WB_GAP_ZERO_PCT",   wb.gap_zero_pct);
    knob_int("UART_WB_STB_DELAY_PCT",  wb.stb_delay_pct);
    knob_int("UART_WB_STB_DELAY_MAX",  wb.stb_delay_max);
    knob_int("UART_WB_BAD_SEL_PCT",    wb.bad_sel_pct);

    // reset
    knob_int("UART_RST_PCT",           rst_pct);
    knob_int("UART_RST_WIDTH_MAX",     rst_width_max);

    // scoreboard y cobertura
    knob_scb_en("UART_SCB_EN");
    knob_int("UART_SCB_MAX_ERRORS",    scb.max_errors);
    knob_sev("UART_SCB_DUT_BUG_SEV");
    knob_bit("UART_COV_EN",            cov.enable);
    knob_int("UART_COV_CURVE_EVERY",   cov.curve_every);

    // ---------------- validaciones ----------------
    check_range("UART_SEQ_EP_MIN", ep_min, "UART_SEQ_EP_MAX", ep_max);
    if (ep_max == 0) `uvm_fatal("KNOB", "+UART_SEQ_EP_MAX tiene que ser al menos 1")
    check_range("UART_SW_DELAY_MIN", sw_delay_min, "UART_SW_DELAY_MAX", sw_delay_max);
    check_range("UART_SER_BAUD_OUT_MIN", ser.baud_out_min, "UART_SER_BAUD_OUT_MAX", ser.baud_out_max);
    if (tx_len_max < 17) `uvm_fatal("KNOB", "+UART_TX_LEN_MAX tiene que ser al menos 17 para poder desbordar la FIFO")
    if (ser.glitch_w_max < 1 || ser.glitch_w_max > 15) `uvm_fatal("KNOB", "+UART_SER_GLITCH_W_MAX va de 1 a 15")
    if (line.dl_max > 65535) `uvm_fatal("KNOB", "+UART_DL_MAX va hasta 65535")
    if (line.dl_zero_pct * 10 + line.dl_tail_w[0] + line.dl_tail_w[1] + line.dl_tail_w[2] > 1000)
      `uvm_fatal("KNOB", "+UART_DL_ZERO_PCT y +UART_DL_TAIL_W suman más de 100 %")
    check_pct("UART_DL_ZERO_PCT",        line.dl_zero_pct);
    check_pct("UART_DL_LSB_FIRST_PCT",   line.dl_lsb_first_pct);
    check_pct("UART_FCR_CLR_PCT",        ctrl.fcr_clr_pct);
    foreach (ctrl.ier_bit_pct[i]) check_pct("UART_IER_BIT_PCT", ctrl.ier_bit_pct[i]);
    check_pct("UART_MCR_OUT_PCT",        ctrl.mcr_out_pct);
    check_pct("UART_MCR_LOOP_PCT",       ctrl.mcr_loop_pct);
    check_pct("UART_SW_PARTIAL_PCT",     sw_partial_pct);
    check_pct("UART_SW_LSR_FIRST_PCT",   sw_lsr_first_pct);
    check_pct("UART_TX_BLIND_PCT",       tx_blind_pct);
    check_pct("UART_TX_BREAK_PCT",       tx_break_pct);
    check_pct("UART_DATA_CORNER_PCT",    data_corner_pct);
    check_pct("UART_SER_PARITY_ERR_PCT", ser.parity_err_pct);
    check_pct("UART_SER_FRAME_ERR_PCT",  ser.frame_err_pct);
    check_pct("UART_SER_BREAK_PCT",      ser.break_pct);
    check_pct("UART_SER_GLITCH_PCT",     ser.glitch_pct);
    check_pct("UART_SER_BAUD_IN_PCT",    ser.baud_in_pct);
    check_pct("UART_SER_BAUD_OUT_PCT",   ser.baud_out_pct);
    check_pct("UART_SER_SHORT_STOP_PCT", ser.short_stop_pct);
    check_pct("UART_MDM_MULTI_PCT",      mdm.multi_pct);
    check_pct("UART_REG_NOISE_PCT",      reg_noise_pct);
    check_pct("UART_REG_DLAB_PCT",       reg_dlab_pct);
    check_pct("UART_REG_RECONFIG_PCT",   reconfig_pct);
    check_pct("UART_REG_FIFO_CLR_PCT",   fifo_clr_mid_pct);
    check_pct("UART_WB_GAP_ZERO_PCT",    wb.gap_zero_pct);
    check_pct("UART_WB_STB_DELAY_PCT",   wb.stb_delay_pct);
    check_pct("UART_WB_BAD_SEL_PCT",     wb.bad_sel_pct);
    check_pct("UART_RST_PCT",            rst_pct);
    // los errores RX se sortean por carácter con un solo número de 0 a 99
    if (ser.parity_err_pct + ser.frame_err_pct + ser.break_pct + ser.glitch_pct +
        ser.baud_in_pct + ser.baud_out_pct > 100)
      `uvm_fatal("KNOB", "la suma de los porcentajes de error de +UART_SER_* pasa de 100")
  endfunction

  function void print_knobs();
    string s = "\nKnobs de la corrida (valor y origen):\n";
    foreach (knob_rows[i]) s = {s, knob_rows[i], "\n"};
    `uvm_info("KNOBS", s, UVM_NONE)
  endfunction
endclass : uart_env_cfg
