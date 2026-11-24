
//
`uvm_analysis_imp_decl(_wb)
`uvm_analysis_imp_decl(_rst)
`uvm_analysis_imp_decl(_int)
`uvm_analysis_imp_decl(_tx)
`uvm_analysis_imp_decl(_rx)
`uvm_analysis_imp_decl(_mdm)

// un caracter esperado, chk = 0 si no es predecible y solo se cuenta
typedef struct {
  bit [7:0] data;
  bit       chk;
  bit       pisado;  // una escritura con la FIFO llena le cayo encima (AMB-10)
  bit [7:0] orig;    // lo que se escribio de verdad, para el mensaje
} uart_exp_t;

class uart_scoreboard extends uvm_scoreboard;
    // Registro en la Factory
  `uvm_component_utils(uart_scoreboard)

  uart_scb_cfg cfg;

  uart_exp_t tx_q[$];        // escritos en THR que todavia no salen por stx
  uart_exp_t rx_q[$];        // vistos en srx que todavia no se leen de RBR
  uart_exp_t tx_alt[$];      // la otra version de tx_q cuando no sabemos si el DUT ya saco uno
  bit        alt_on;

  bit [7:0] exp_lsr;         // Estado esperado del Line Status Register
  bit [7:0] exp_iir;         // Estado esperado del Interrupt Identification Register
  bit [7:0] exp_msr;         // Estado esperado del Modem Status Register

  bit       dlab_bit;        // Rastreo del bit DLAB para resolver direcciones
  bit [7:0] lcr_val;         // LCR y MCR segun lo que paso por el bus
  bit [7:0] mcr_val;
  bit       tx_dirty;        // hubo reconfig, limpieza o reset con trafico, no se compara hasta el fin del episodio
  bit       rx_dirty;
  bit       rx_seen;         // ya llego algun caracter por srx en este episodio
  bit       rst_tx_busy, rst_rx_busy;
  int       error_count;
  int       n_tx_ok, n_rx_ok, n_skip;

  // Puertos TLM
  uvm_analysis_imp_wb  #(wb_item, uart_scoreboard)       wb_imp;
  uvm_analysis_imp_rst #(wb_rst_item, uart_scoreboard)   rst_imp;
  uvm_analysis_imp_int #(uart_int_item, uart_scoreboard) int_imp;
  uvm_analysis_imp_tx  #(ser_item, uart_scoreboard)      tx_imp;
  uvm_analysis_imp_rx  #(ser_item, uart_scoreboard)      rx_imp;
  uvm_analysis_imp_mdm #(mdm_item, uart_scoreboard)      mdm_imp;
  uvm_analysis_port    #(uart_model_evt)                 ap;

  function new(string name = "uart_scoreboard", uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(uart_scb_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("NO_CFG", "Falta uart_scb_cfg en el scoreboard")
    end
    wb_imp  = new("wb_imp", this);
    rst_imp = new("rst_imp", this);
    int_imp = new("int_imp", this);
    tx_imp  = new("tx_imp", this);
    rx_imp  = new("rx_imp", this);
    mdm_imp = new("mdm_imp", this);
    ap      = new("ap", this);
    reset_model();
  endfunction

  // al final de cada episodio la secuencia ya vacio TX y RX, asi que ahi revisamos y empezamos limpio
  virtual task run_phase(uvm_phase phase);
    uvm_event ep_end = uvm_event_pool::get_global("uart_ep_end");
    forever begin
      ep_end.wait_trigger();
      check_left("fin de episodio");
      tx_q.delete();
      rx_q.delete();
      alt_on   = 0;
      tx_dirty = 0;
      rx_dirty = 0;
      rx_seen  = 0;
    end
  endtask

  function void reset_model();
    alt_on = 0;
    tx_q.delete();
    rx_q.delete();
    exp_lsr  = 8'h60; // THRE y TEMT en 1 (transmisor vacío)
    exp_iir  = 8'hC1; // Sin interrupciones pendientes
    exp_msr  = 8'h00;
    dlab_bit = 1'b0;
    lcr_val  = 8'h03;  // valor de reset del RTL
    mcr_val  = 8'h00;
  endfunction

  function bit [7:0] data_mask();
    return 8'hFF >> (3 - lcr_val[1:0]);
  endfunction

  function bit tx_busy(); return tx_q.size() > 0; endfunction
  function bit rx_busy(); return rx_q.size() > 0; endfunction

  // lo que quedo esperando al final es que nunca llego
  function void check_left(string donde);
    int n_tx = 0, n_rx = 0;
    if (!tx_dirty) foreach (tx_q[i]) if (tx_q[i].chk) n_tx++;
    if (!rx_dirty) foreach (rx_q[i]) if (rx_q[i].chk) n_rx++;
    if (n_tx > 0) begin
      error_count++;
      `uvm_error("SCB_TX", $sformatf("%s: quedaron %0d caracteres escritos en THR que nunca salieron por stx", donde, n_tx))
    end
    if (n_rx > 0) begin
      error_count++;
      `uvm_error("SCB_RX", $sformatf("%s: quedaron %0d caracteres recibidos que nunca se leyeron de RBR", donde, n_rx))
    end
  endfunction

  // desde aqui no se compara lo que este en camino, se cuenta nada mas
  function void ensuciar_tx(string porque);
    if (!tx_busy() || tx_dirty) return;
    tx_dirty = 1;
    alt_on   = 0;
    foreach (tx_q[i]) tx_q[i].chk = 0;
    `uvm_info("SCB", {"TX no predecible hasta el fin del episodio: ", porque}, UVM_MEDIUM)
  endfunction

  function void ensuciar_rx(string porque);
    if (!(rx_busy() || rx_seen) || rx_dirty) return;
    rx_dirty = 1;
    foreach (rx_q[i]) rx_q[i].chk = 0;
    `uvm_info("SCB", {"RX no predecible hasta el fin del episodio: ", porque}, UVM_MEDIUM)
  endfunction

  function void pisar(ref uart_exp_t q[$], input int idx, input bit [7:0] data);
    if (!q[idx].pisado) q[idx].orig = q[idx].data;
    q[idx].pisado = 1;
    q[idx].data   = data;
  endfunction

  function void dut_bug(string msg);
    if (cfg.dut_bug_sev == UVM_ERROR) `uvm_error("DUT_BUG", {"AMB-10: ", msg})
    else                              `uvm_warning("DUT_BUG", {"AMB-10: ", msg})
  endfunction

  function void send_evt(uart_evt_e kind, int unsigned tx_lvl, int unsigned rx_lvl, bit lost);
    uart_model_evt evt = uart_model_evt::type_id::create("evt");
    evt.kind     = kind;
    evt.tx_level = tx_lvl;
    evt.rx_level = rx_lvl;
    evt.lost     = lost;
    evt.tx_busy  = tx_busy();
    evt.rx_busy  = rx_busy();
    ap.write(evt);
  endfunction

  // Manejo del Reset

  virtual function void write_rst(wb_rst_item item);
    uart_model_evt evt;

    if (item.asserted) begin
      rst_tx_busy = tx_busy();
      rst_rx_busy = rx_busy() || rx_seen;
      // un caracter cortado por el reset igual lo pueden reportar los monitores
      if (!item.is_initial) begin
        tx_dirty = 1;
        rx_dirty = 1;
      end
      reset_model();
    end else begin
      // el ancho del reset solo se sabe cuando baja
      evt = uart_model_evt::type_id::create("evt");
      evt.kind       = EV_RESET;
      evt.rst_cycles = item.width_cycles;
      evt.tx_busy    = rst_tx_busy;
      evt.rx_busy    = rst_rx_busy;
      ap.write(evt);
    end
  endfunction

  // 2. Manejo del Bus Wishbone (CPU accediendo a registros)

  virtual function void write_wb(wb_item item);
    bit [4:0] reg_idx;
    bit [7:0] dat8, rd8;
    uart_exp_t exp;
    int unsigned lvl;

    // Ignorar accesos abortados o que no recibieron ack a tiempo
    if (item.timeout || item.aborted) return;

    // el registro y el byte que de verdad uso el DUT, igual que la cobertura
    reg_idx = uart_reg_of(item.adr, item.sel);
    dat8    = uart_lane8(item.sel, item.dat);
    rd8     = uart_lane8(item.sel, item.dat_rd);

    if (item.we) begin
      case (reg_idx)
        UART_LCR: begin
          if (dat8[6:0] != lcr_val[6:0]) begin
            ensuciar_tx("cambio de LCR");
            ensuciar_rx("cambio de LCR");
          end
          lcr_val  = dat8;
          dlab_bit = dat8[7];
        end
        UART_MCR: begin
          if (dat8[4] != mcr_val[4]) begin
            ensuciar_tx("cambio de loopback");
            ensuciar_rx("cambio de loopback");
          end
          mcr_val = dat8;
        end
        UART_FCR: begin   // el RTL escribe FCR sin importar DLAB
          // el caracter en curso no se corta, pero no sabemos cuantos quedaban en la FIFO
          if (dat8[2]) ensuciar_tx("limpieza de la FIFO TX");
          if (dat8[1]) begin
            ensuciar_rx("limpieza de la FIFO RX");
            rx_q.delete();
          end
        end
        default: ;
      endcase

      // escribir DLL o DLM reinicia el contador de baudios aunque el valor sea el mismo
      if (dlab_bit && (reg_idx == UART_DLL || reg_idx == UART_DLM)) begin
        ensuciar_tx("escritura de DL");
        ensuciar_rx("escritura de DL");
      end

      // ESCRITURA EN THR (DLAB = 0)
      if (reg_idx == UART_THR && !dlab_bit) begin
        lvl = tx_q.size();
        exp.data  = dat8 & data_mask();
        exp.chk   = !tx_dirty;
        exp.pisado = 0;
        if (mcr_val[4]) begin
          // en loopback el caracter vuelve por el receptor y no sale por stx
          exp.chk = 0;
          rx_q.push_back(exp);
          send_evt(EV_THR_WRITE, lvl, rx_q.size(), 0);
          return;
        end
        // caben 16 en la FIFO mas 1 en el registro de corrimiento. Con 16 en cola no sabemos
        // si el transmisor ya saco el primero, entonces llevamos las dos versiones
        if (lvl == 16 && !tx_dirty) begin
          if (alt_on) ensuciar_tx("dos dudas seguidas con la FIFO TX llena");
          else begin
            alt_on = 1;
            tx_alt = tx_q;
            pisar(tx_alt, 0, exp.data);   // si no lo habia sacado, este se perdio
          end
        end
        if (lvl >= 17) begin
          // el RTL escribe la RAM aunque este llena y pisa el siguiente que iba a salir
          if (!tx_dirty) pisar(tx_q, 1, exp.data);
          if (alt_on)    pisar(tx_alt, 0, exp.data);
          send_evt(EV_THR_WRITE, 16, rx_q.size(), 1);
          return;
        end
        exp.chk = !tx_dirty;   // pudo cambiar arriba
        tx_q.push_back(exp);
        if (alt_on && lvl != 16) tx_alt.push_back(exp);
        send_evt(EV_THR_WRITE, lvl, rx_q.size(), 0);
      end
    end
    else begin
      // LECTURA DE RBR (DLAB = 0)
      if (reg_idx == UART_RBR && !dlab_bit) begin
        lvl = rx_q.size();
        // leer con la FIFO vacia no se compara (V-RX-05)
        if (lvl > 0) begin
          exp = rx_q.pop_front();
          if (exp.chk && cfg.chk_rx) begin
            if ((rd8 & data_mask()) !== exp.data) begin
              error_count++;
              `uvm_error("SCB_RX", $sformatf("RBR leyo %02h y se esperaba %02h (%s)", rd8 & data_mask(), exp.data, cfg.line.convert2string()))
            end else if (exp.pisado) begin
              dut_bug($sformatf("RBR leyo %02h, que llego con la FIFO RX llena, en vez de %02h", exp.data, exp.orig));
            end else n_rx_ok++;
          end else n_skip++;
        end
        send_evt(EV_RBR_READ, tx_q.size(), lvl, 0);
      end
    end
  endfunction

  // caracter que salio por stx, tiene que ser el primero que se escribio en THR
  virtual function void write_tx(ser_item item);
    uart_exp_t exp, alt;
    bit [7:0]  got;
    bit        es_h1, es_h0;

    if (item.err == SER_BREAK) return;   // break de LCR[6], no es un caracter
    got = item.data & data_mask();

    if (tx_q.size() == 0) begin
      if (tx_dirty) return;
      error_count++;
      `uvm_error("SCB_TX", $sformatf("salio %02h por stx sin que nadie lo escribiera en THR", got))
      return;
    end

    exp = tx_q.pop_front();
    if (alt_on && tx_alt.size() > 0) begin
      alt   = tx_alt.pop_front();
      es_h1 = (got == exp.data);
      es_h0 = (got == alt.data);
      if (es_h0 && !es_h1) begin   // el transmisor no habia sacado el primero
        exp  = alt;
        tx_q = tx_alt;
      end
      if (!(es_h0 && es_h1)) alt_on = 0;   // si calzan las dos seguimos con la duda
    end
    if (!exp.chk || !cfg.chk_tx) begin
      n_skip++;
      return;
    end

    if (got !== exp.data) begin
      error_count++;
      `uvm_error("SCB_TX", $sformatf("stx saco %02h y se esperaba %02h (%s)", got, exp.data, cfg.line.convert2string()))
    end else if (item.err != SER_OK) begin
      error_count++;
      `uvm_error("SCB_TX", $sformatf("el caracter %02h salio con error %s", got, item.err.name()))
    end else if (exp.pisado) begin
      dut_bug($sformatf("stx saco %02h, que se escribio con la FIFO TX llena, en vez de %02h", got, exp.orig));
    end else n_tx_ok++;
  endfunction

  // caracter que entro por srx, el DUT lo mete a la FIFO RX
  virtual function void write_rx(ser_item item);
    uart_exp_t exp;
    int unsigned lvl = rx_q.size();

    if (mcr_val[4]) return;   // en loopback el DUT ignora srx
    rx_seen = 1;

    // overrun: el nuevo no entra, pero el RTL lo escribe en la RAM encima del mas viejo
    if (lvl >= 16) begin
      if (!rx_q[0].pisado) rx_q[0].orig = rx_q[0].data;
      rx_q[0].pisado = 1;
      rx_q[0].data   = item.data & data_mask();
      if (item.err inside {SER_BAUD_OUT, SER_GLITCH_START}) rx_q[0].chk = 0;
      send_evt(EV_RX_PUSH, tx_q.size(), lvl, 1);
      return;
    end

    exp.data   = item.data & data_mask();
    exp.pisado = 0;
    // fuera de tolerancia o falso inicio, el DUT pudo leer otra cosa
    exp.chk   = !rx_dirty && !(item.err inside {SER_BAUD_OUT, SER_GLITCH_START});
    rx_q.push_back(exp);
    send_evt(EV_RX_PUSH, tx_q.size(), lvl, 0);
  endfunction

  // (write_mdm y write_int se mantienen vacías por ahora)
  virtual function void write_int(uart_int_item item); endfunction
  virtual function void write_mdm(mdm_item item); endfunction

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    check_left("fin de la prueba");
  endfunction

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB", $sformatf("TX bien: %0d, RX bien: %0d, sin comparar: %0d, errores: %0d",
              n_tx_ok, n_rx_ok, n_skip, error_count), UVM_LOW)
  endfunction
endclass : uart_scoreboard
