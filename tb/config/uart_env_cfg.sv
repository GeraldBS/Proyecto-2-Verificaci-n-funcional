//////////////////////////////////////////////////////////////////////
// uart_env_cfg:
// Configuración de todo el ambiente. Es el único lugar que lee plusargs
// y crea los objetos de línea, FIFO, agentes,
// scoreboard y cobertura, que comparten el formato vigente.
//////////////////////////////////////////////////////////////////////

class uart_env_cfg extends uvm_object; // Crea el ambiente
  `uvm_object_utils(uart_env_cfg)

  // objetos que cuelgan de este (la prueba los publica por separado)
  uart_line_cfg      line;
  uart_ctrl_cfg      ctrl;
  wb_agent_cfg       wb;
  uart_ser_agent_cfg ser;
  modem_agent_cfg    mdm;
  uart_scb_cfg       scb;
  uart_cov_cfg       cov;

  // no tienen plusarg, los fija el codigo de cada prueba
  int unsigned n_episodes  = 1;
  bit          frame_sweep = 0;   // solo uart_frame_sweep_test
  int unsigned seed        = 1;   // se lee de +ntb_random_seed, la usa el barrido de formatos

  int unsigned ep_timeout_tc = 2000;

  // software que atiende al UART
  int unsigned sw_mode          = 0;                // 0 sortea, 1 interrupciones, 2 sondeo
  int unsigned sw_delay_min     = 0;                // Tc
  int unsigned sw_partial_pct   = 20;
  int unsigned sw_delay_max     = 24;               // Tc, constante
  int unsigned sw_delay_w[]     = '{70, 22, 8};     // 0-1, 2-6, 7-max Tc
  int unsigned sw_poll_max      = 4;                // Tc
  int unsigned sw_lsr_first_pct = 80;

  // transmisión
  int unsigned tx_ovf_pct      = 15;                // rafagas de 17 a 20
  int unsigned tx_blind_pct    = 30;
  int unsigned tx_break_pct    = 5;
  int unsigned tx_bursts_max   = 6;
  int unsigned tx_len_max      = 20;
  int unsigned tx_gap_max      = 4;                 // Tc
  int unsigned tx_break_max    = 4;                 // Tc
  int unsigned data_corner_pct = 20;

  // accesos a registros y eventos raros
  int unsigned reg_noise_pct    = 10;
  int unsigned reconfig_pct     = 10;
  int unsigned fifo_clr_mid_pct = 10;
  int unsigned reg_dlab_pct     = 20;

  // reset asíncrono en medio del episodio
  int unsigned rst_pct       = 10;
  int unsigned rst_width_max = 5;

  // filas de la tabla que imprime print_knobs()
  string knob_rows[$];

  function new(string name = "uart_env_cfg"); // constructor (agentes, covertura, scorboard, entre otras)
    super.new(name);
    line = uart_line_cfg::type_id::create("line");
    ctrl = uart_ctrl_cfg::type_id::create("ctrl");
    wb   = wb_agent_cfg::type_id::create("wb");
    ser  = uart_ser_agent_cfg::type_id::create("ser");
    mdm  = modem_agent_cfg::type_id::create("mdm");
    scb  = uart_scb_cfg::type_id::create("scb");
    cov  = uart_cov_cfg::type_id::create("cov");

    // todos ven el mismo formato 
    ser.line = line;
    scb.line = line;  scb.ctrl = ctrl;
    cov.line = line;  cov.ctrl = ctrl;
  endfunction

  local function bit get_str(string name, output string val);
    uvm_cmdline_processor clp = uvm_cmdline_processor::get_inst();
    return clp.get_arg_value({"+", name, "="}, val) != 0;
  endfunction

  // VCS limita el ancho de campo de $sformatf, así que rellenamos a mano
  local function string pad(string s, int unsigned w);
    while (s.len() < w) s = {s, " "};
    return s;
  endfunction

  // leen un plusarg y arman la tabla de knobs
  local function void add_row(string name, string val, bit found);
    knob_rows.push_back({"  +", pad(name, 26), " = ", pad(val, 16), found ? "plusarg" : "defecto"});
  endfunction

  local function void knob_int(string name, ref int unsigned v);
    string s;
    bit    found = get_str(name, s);
    if (found) v = s.atoi();
    add_row(name, $sformatf("%0d", v), found);
  endfunction

  // para los que aceptan -1 (sortear)
  local function void knob_sint(string name, ref int v);
    string s;
    bit    found = get_str(name, s);
    if (found) v = s.atoi();
    add_row(name, $sformatf("%0d", v), found);
  endfunction

  local function void knob_hex(string name, ref bit [3:0] v);
    string s;
    bit    found = get_str(name, s);
    if (found) v = s.atohex();
    add_row(name, $sformatf("%0h", v), found);
  endfunction

  local function void check_pct(string name, int unsigned v);
    if (v > 100) `uvm_fatal("KNOB", $sformatf("+%s=%0d: tiene que estar entre 0 y 100", name, v))
  endfunction

  // lee el plusarg de severidad

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

  // único punto de lectura de plusargs
  function void parse_plusargs();
    string s;
    knob_rows.delete();
    if (get_str("ntb_random_seed", s)) seed = s.atoi();

    knob_int("UART_SEQ_EP_TIMEOUT",      ep_timeout_tc);

    // formato de línea y divisor
    knob_sint("UART_LCR_WLS",            line.lcr_wls);
    knob_int("UART_DL_MIN",              line.dl_min);
    knob_int("UART_DL_MAX",              line.dl_max);

    // FIFO, interrupciones y módem
    knob_sint("UART_FCR_TL",             ctrl.fcr_tl);
    knob_hex("UART_IER_ON",              ctrl.ier_on);
    knob_int("UART_MCR_LOOP_PCT",        ctrl.mcr_loop_pct);

    // software
    knob_int("UART_SW_MODE",             sw_mode);
    knob_int("UART_SW_DELAY_MIN",        sw_delay_min);
    knob_int("UART_SW_PARTIAL_PCT",      sw_partial_pct);

    // transmisión
    knob_int("UART_TX_OVF_PCT",          tx_ovf_pct);
    knob_int("UART_TX_BLIND_PCT",        tx_blind_pct);
    knob_int("UART_TX_BREAK_PCT",        tx_break_pct);

    // agente serie
    knob_int("UART_SER_RX_GAP",          ser.rx_gap_mode);
    knob_int("UART_SER_PARITY_ERR_PCT",  ser.parity_err_pct);
    knob_int("UART_SER_BREAK_PCT",       ser.break_pct);
    knob_int("UART_SER_GLITCH_PCT",      ser.glitch_pct);
    knob_int("UART_SER_BAUD_IN_PCT",     ser.baud_in_pct);
    knob_int("UART_SER_BAUD_OUT_PCT",    ser.baud_out_pct);
    knob_int("UART_SER_SHORT_STOP_PCT",  ser.short_stop_pct);

    knob_int("UART_MDM_CHANGES_MAX",     mdm.changes_max);

    // registros y eventos raros
    knob_int("UART_REG_NOISE_PCT",       reg_noise_pct);
    knob_int("UART_REG_RECONFIG_PCT",    reconfig_pct);
    knob_int("UART_REG_FIFO_CLR_PCT",    fifo_clr_mid_pct);
    knob_int("UART_RST_PCT",             rst_pct);
    knob_int("UART_WB_BAD_SEL_PCT",      wb.bad_sel_pct);

    knob_sev("UART_SCB_DUT_BUG_SEV");

    // validaciones, si algo esta fuera de rango mejor parar de una vez
    if (ep_timeout_tc == 0) `uvm_fatal("KNOB", "+UART_SEQ_EP_TIMEOUT tiene que ser al menos 1")
    if (line.lcr_wls < -1 || line.lcr_wls > 3) `uvm_fatal("KNOB", "+UART_LCR_WLS va de -1 a 3")
    if (ctrl.fcr_tl < -1 || ctrl.fcr_tl > 3)   `uvm_fatal("KNOB", "+UART_FCR_TL va de -1 a 3")
    if (line.dl_max > 65535) `uvm_fatal("KNOB", "+UART_DL_MAX va hasta 65535")
    if (line.dl_min > line.dl_max)
      `uvm_fatal("KNOB", $sformatf("+UART_DL_MIN=%0d es mayor que +UART_DL_MAX=%0d", line.dl_min, line.dl_max))
    if (sw_mode > 2)      `uvm_fatal("KNOB", "+UART_SW_MODE va de 0 a 2")
    if (sw_delay_min > sw_delay_max) `uvm_fatal("KNOB", "+UART_SW_DELAY_MIN va de 0 a 24")
    if (ser.rx_gap_mode > 2) `uvm_fatal("KNOB", "+UART_SER_RX_GAP va de 0 a 2")
    check_pct("UART_MCR_LOOP_PCT",       ctrl.mcr_loop_pct);
    check_pct("UART_SW_PARTIAL_PCT",     sw_partial_pct);
    check_pct("UART_TX_OVF_PCT",         tx_ovf_pct);
    check_pct("UART_TX_BLIND_PCT",       tx_blind_pct);
    check_pct("UART_TX_BREAK_PCT",       tx_break_pct);
    check_pct("UART_SER_PARITY_ERR_PCT", ser.parity_err_pct);
    check_pct("UART_SER_BREAK_PCT",      ser.break_pct);
    check_pct("UART_SER_GLITCH_PCT",     ser.glitch_pct);
    check_pct("UART_SER_BAUD_IN_PCT",    ser.baud_in_pct);
    check_pct("UART_SER_BAUD_OUT_PCT",   ser.baud_out_pct);
    check_pct("UART_SER_SHORT_STOP_PCT", ser.short_stop_pct);
    check_pct("UART_REG_NOISE_PCT",      reg_noise_pct);
    check_pct("UART_REG_RECONFIG_PCT",   reconfig_pct);
    check_pct("UART_REG_FIFO_CLR_PCT",   fifo_clr_mid_pct);
    check_pct("UART_RST_PCT",            rst_pct);
    check_pct("UART_WB_BAD_SEL_PCT",     wb.bad_sel_pct);
    // los errores RX se sortean por caracter con un solo numero de 0 a 99, incluida la trama que es fija en 5
    if (ser.parity_err_pct + ser.frame_err_pct + ser.break_pct + ser.glitch_pct +
        ser.baud_in_pct + ser.baud_out_pct > 100)
      `uvm_fatal("KNOB", "la suma de los porcentajes de error de +UART_SER_* (mas 5 de trama) pasa de 100")
  endfunction

  // imprime resultados
  function void print_knobs();
    string s = "\nKnobs de la corrida (valor y origen):\n";
    foreach (knob_rows[i]) s = {s, knob_rows[i], "\n"};
    s = {s, $sformatf("  episodios = %0d%s, semilla = %0d\n", n_episodes,
                      frame_sweep ? " (barrido de formatos)" : "", seed)};
    `uvm_info("KNOBS", s, UVM_NONE)
  endfunction
endclass : uart_env_cfg
