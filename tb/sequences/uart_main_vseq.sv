//////////////////////////////////////////////////////////////////////////////
// uart_main_vseq:
// Secuencia principal de la prueba: revisa los valores de reset con el RAL y corre n_episodios.
// Cada episodio sortea y programa el UART, lanza TX, RX, módem, software y eventos en paralelo
// con un límite de tiempo, y después drena; si hubo reset, reprograma y manda unos caracteres.
//////////////////////////////////////////////////////////////////////////////

class uart_main_vseq extends uart_base_vseq;
  `uvm_object_utils(uart_main_vseq)

  function new(string name = "uart_main_vseq");
    super.new(name);
  endfunction

  task body();
    uvm_reg_hw_reset_seq rs;
    wait (p_sequencer.cfg.wb.vif.rst === 1'b0);
    wait_cycles(2);

    if (p_sequencer.regm != null) begin   // la revisión de reset va siempre
      rs = uvm_reg_hw_reset_seq::type_id::create("rs");
      rs.model = p_sequencer.regm;
      rs.start(null, this);
    end

    for (int ep = 1; ep <= cfg().n_episodes; ep++) begin
      p_sequencer.episode = ep;
      // semilla k: formatos 4*(k mod 10) a 4*(k mod 10)+3 (CE-05)
      if (cfg().frame_sweep) line().fmt = 4 * (cfg().seed % 10) + ep - 1;
      run_episode();
      uvm_event_pool::get_global("uart_ep_end").trigger(); // la cobertura imprime [COV_CURVE] con esto
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
    bit               slow;
    bit               sweep = cfg().frame_sweep;
    uart_ctrl_cfg     c;

    p_sequencer.traffic_done = 0;
    p_sequencer.rst_hit      = 0;
    if (!line().randomize()) `uvm_fatal("RAND", "no se pudo aleatorizar uart_line_cfg")
    c = ctrl();   // handle local: el with { } no resuelve nombres sobre el resultado de una función
    if (!c.randomize() with { local::sweep -> loop == 0; })   // en loopback no habría RX en el barrido
      `uvm_fatal("RAND", "no se pudo aleatorizar uart_ctrl_cfg")
    prog.start(p_sequencer, this); // los agentes ven el formato nuevo por la referencia compartida

    // con DL >= 256 un carácter dura demasiado, así que poco tráfico
    slow = (line().dl >= cfg().ser.slow_dl);
    tx.n_bursts    = slow ? 1 : $urandom_range(cfg().tx_bursts_max, 0);
    tx.max_len     = slow ? 2 : 0;
    tx.do_break    = pct(cfg().tx_break_pct);
    rx.n_chars     = ctrl().loop ? 0 :   // en loopback el DUT ignora srx
                     slow ? $urandom_range(cfg().ser.slow_chars_max, 0) : $urandom_range(cfg().ser.rx_chars_max, 0);
    mdm.n_changes  = $urandom_range(cfg().mdm.changes_max, 0);
    case (cfg().sw_mode)
      1:       sw.mode = SW_IRQ;
      2:       sw.mode = SW_POLL;
      default: sw.mode = $urandom_range(1) ? SW_IRQ : SW_POLL;
    endcase
    cfg().cov.sw_mode = sw.mode;
    evt.do_reconfig = pct(cfg().reconfig_pct);
    evt.do_fifo_clr = pct(cfg().fifo_clr_mid_pct);
    evt.do_reset    = pct(cfg().rst_pct);

    // el barrido necesita TX y RX en cada formato, con un error de paridad y uno de trama
    if (cfg().frame_sweep) begin
      if (tx.n_bursts == 0) tx.n_bursts = 1;
      if (rx.n_chars < 2)   rx.n_chars  = 2;
      rx.force_errs   = 1;
      evt.do_reconfig = 0;   // si no, el formato cambia a medias
    end
    evt.window_tc = 1 + rx.n_chars + tx.n_bursts * 8;   // después del barrido, con la cantidad final de tráfico

    `uvm_info("EP", $sformatf("episodio %0d: tx %0d ráfagas, rx %0d caracteres, módem %0d cambios, %s%s%s%s",
              p_sequencer.episode, tx.n_bursts, rx.n_chars, mdm.n_changes, sw.mode.name(),
              evt.do_reconfig ? ", reconfig" : "", evt.do_fifo_clr ? ", limpia FIFO" : "",
              evt.do_reset ? ", reset" : ""), UVM_LOW)

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
      p_sequencer.bus_sem = new(1); // si alguien quedó con el candado del bus lo soltamos
    end

    if (p_sequencer.rst_hit) after_reset();
    drain();
  endtask

  // después del reset el UART vuelve a valores por defecto, lo reprogramamos
  // igual que antes y mandamos 1 o 2 caracteres para ver que se recuperó
  task after_reset();
    uart_program_vseq prog = uart_program_vseq::type_id::create("prog_rst");
    uart_tx_vseq      tx   = uart_tx_vseq::type_id::create("tx_rst");
    uart_rx_vseq      rx   = uart_rx_vseq::type_id::create("rx_rst");
    wait (p_sequencer.cfg.wb.vif.rst === 1'b0);
    wait_cycles(2);
    if (p_sequencer.regm != null) p_sequencer.regm.reset();
    p_sequencer.rst_hit = 0;
    prog.start(p_sequencer, this);
    tx.n_bursts = 1;
    tx.max_len  = 2;
    rx.n_chars  = ctrl().loop ? 0 : $urandom_range(2, 1);
    rx.no_errs  = 1;
    fork
      tx.start(p_sequencer, this);
      rx.start(p_sequencer, this);
    join
    `uvm_info("EP", "UART reprogramado después del reset", UVM_MEDIUM)
  endtask

  // espera que salga lo transmitido, vacía la FIFO RX y lee LSR, MSR e IIR
  task drain();
    bit [7:0] lsr, dummy;
    if (line().dl != 0) begin   // con DL = 0 el UART no transmite, no hay nada que esperar
      for (int i = 0; i < 64; i++) begin   // TEMT, con límite por si el UART se traba
        wb_read(UART_LSR, lsr);
        if (lsr[6]) break;
        wait_tc(1);
      end
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