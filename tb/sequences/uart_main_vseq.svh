//////////////////////////////////////////////////////////////////////
// uart_main_vseq: la secuencia principal de la prueba base         //
//////////////////////////////////////////////////////////////////////
// Son los pasos de la sección 6.3 del plan (pseudocódigo en la 6.17): reset inicial y
// revisión del RAL, y después n episodios de configurar, tráfico en
// paralelo y drenar. Cada episodio tiene un límite de tiempo para que
// un UART trabado no deje la simulación corriendo para siempre.
//////////////////////////////////////////////////////////////////////
class uart_main_vseq extends uart_base_vseq;
  `uvm_object_utils(uart_main_vseq)

  function new(string name = "uart_main_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned n_ep = $urandom_range(cfg().ep_max, cfg().ep_min);
    wait (p_sequencer.cfg.wb.vif.rst === 1'b0);
    wait_cycles(2);

    if (cfg().hw_reset_chk && p_sequencer.regm != null) begin
      uvm_reg_hw_reset_seq rs = uvm_reg_hw_reset_seq::type_id::create("rs");
      rs.model = p_sequencer.regm;
      rs.start(null, this);
    end

    for (int ep = 1; ep <= n_ep; ep++) begin
      p_sequencer.episode = ep;
      run_episode();
      // la cobertura imprime su línea [COV_CURVE] con este aviso
      uvm_event_pool::get_global("uart_ep_end").trigger();
    end
  endtask

  task run_episode();
    uart_program_vseq prog = uart_program_vseq::type_id::create("prog");
    uart_tx_vseq      tx   = uart_tx_vseq::type_id::create("tx");
    uart_rx_vseq      rx   = uart_rx_vseq::type_id::create("rx");
    uart_mdm_vseq     mdm  = uart_mdm_vseq::type_id::create("mdm");
    uart_sw_vseq      sw   = uart_sw_vseq::type_id::create("sw");
    uart_events_vseq  evt  = uart_events_vseq::type_id::create("evt");
    bit               timed_out = 0;

    // 1. configuración nueva
    p_sequencer.traffic_done = 0;
    p_sequencer.rst_hit      = 0;
    if (!line().randomize()) `uvm_fatal("RAND", "no se pudo aleatorizar uart_line_cfg")
    if (!ctrl().randomize()) `uvm_fatal("RAND", "no se pudo aleatorizar uart_ctrl_cfg")

    // 2. programar el UART (y 3. los agentes ven el formato nuevo por la
    // referencia compartida; program_vseq pone el loopback)
    prog.start(p_sequencer, this);

    // plan del episodio, con los knobs
    tx.n_bursts    = $urandom_range(cfg().tx_bursts_max, 0);
    tx.do_break    = pct(cfg().tx_break_pct);
    rx.n_chars     = ctrl().loop ? 0 :   // en loopback el DUT ignora srx
                     (line().dl >= cfg().ser.slow_dl) ? $urandom_range(cfg().ser.slow_chars_max, 0)
                                                      : $urandom_range(cfg().ser.rx_chars_max, 0);
    mdm.n_changes  = $urandom_range(cfg().mdm.changes_max, 0);
    sw.mode        = pick_w(cfg().sw_mode_w) == 0 ? SW_IRQ : SW_POLL;
    cfg().cov.sw_mode = sw.mode;
    evt.do_reconfig = pct(cfg().reconfig_pct);
    evt.do_fifo_clr = pct(cfg().fifo_clr_mid_pct);
    evt.do_reset    = pct(cfg().rst_pct);
    evt.window_tc   = 1 + rx.n_chars + tx.n_bursts * 8;

    `uvm_info("EP", $sformatf("episodio %0d: tx %0d ráfagas, rx %0d caracteres, módem %0d cambios, %s%s%s%s",
              p_sequencer.episode, tx.n_bursts, rx.n_chars, mdm.n_changes, sw.mode.name(),
              evt.do_reconfig ? ", reconfig" : "", evt.do_fifo_clr ? ", limpia FIFO" : "",
              evt.do_reset ? ", reset" : ""), UVM_LOW)

    // 4. actividades en paralelo, con límite de tiempo
    fork : episodio
      begin
        fork
          begin
            fork
              tx.start(p_sequencer, this);
              rx.start(p_sequencer, this);
              mdm.start(p_sequencer, this);
              evt.start(p_sequencer, this);
            join
            p_sequencer.traffic_done = 1;
          end
          sw.start(p_sequencer, this);
        join
      end
      begin
        wait_tc(cfg().ep_timeout_tc);
        timed_out = 1;
      end
    join_any
    disable episodio;

    if (timed_out) begin
      `uvm_error("EP_TIMEOUT", $sformatf("el episodio %0d no terminó en %0d Tc (%s | %s)",
                 p_sequencer.episode, cfg().ep_timeout_tc, line().convert2string(), ctrl().convert2string()))
      // si alguien quedó con el candado del bus, lo liberamos
      p_sequencer.bus_sem = new(1);
    end

    // 5. drenar, o 6. si hubo reset, reiniciar el espejo del RAL
    if (p_sequencer.rst_hit) begin
      wait (p_sequencer.cfg.wb.vif.rst === 1'b0);
      wait_cycles(2);
      if (p_sequencer.regm != null) p_sequencer.regm.reset();
    end else begin
      drain();
    end
  endtask

  // espera que salga todo lo transmitido, vacía la FIFO RX y lee LSR,
  // MSR e IIR para que el episodio siguiente empiece limpio
  task drain();
    bit [7:0] lsr, dummy;
    if (line().dl != 0 && !ctrl().loop) begin
      // TEMT: transmisor vacío. Con un límite por si el UART se traba.
      for (int i = 0; i < 64; i++) begin
        wb_read(UART_LSR, lsr);
        if (lsr[6]) break;
        wait_tc(1);
      end
    end else if (ctrl().loop) begin
      // en loopback lo transmitido vuelve por el receptor
      wait_tc(2);
    end
    for (int i = 0; i < 17; i++) begin
      wb_read(UART_LSR, lsr);
      if (!lsr[0]) break;
      wb_read(UART_RBR, dummy);
    end
    wb_read(UART_MSR, dummy);
    wb_read(UART_IIR, dummy);
  endtask
endclass : uart_main_vseq
