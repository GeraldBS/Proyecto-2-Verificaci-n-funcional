//////////////////////////////////////////////////////////////////////////////////
// uart_act_smoke_pkg.sv
// Prueba de humo de las actividades (fase F4): program, tx, rx, mdm, sw y events.
// Usa el DUT con el agente Wishbone y, en lugar de los agentes serie y de módem, dos
// sumideros que guardan los ser_item y mdm_item que reciben. El tráfico TX vuelve por RX
// con el loopback del MCR, así que no hace falta cablear stx con srx.
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

package uart_act_smoke_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import uart_pkg::*;   // clases del ambiente y constantes UART_* de uart_types.sv

  // Compara un valor con el esperado
  function automatic void act_check(string what, longint got, longint exp);
    if (got !== exp)
      `uvm_error("SMOKE", $sformatf("%s: obtuvo 0x%0h, esperaba 0x%0h", what, got, exp))
    else
      `uvm_info("SMOKE", $sformatf("%s = 0x%0h OK", what, got), UVM_LOW)
  endfunction

  // Comprueba que un valor esté en [lo:hi]
  function automatic void act_range(string what, longint got, longint lo, longint hi);
    if (got < lo || got > hi)
      `uvm_error("SMOKE", $sformatf("%s: obtuvo %0d, esperaba entre %0d y %0d", what, got, lo, hi))
    else
      `uvm_info("SMOKE", $sformatf("%s = %0d OK", what, got), UVM_LOW)
  endfunction

  // Espía de Wishbone: cuenta escrituras a THR y lecturas de RBR y guarda la última escritura a FCR
  class wb_spy extends uvm_subscriber #(wb_item);
    `uvm_component_utils(wb_spy)   // macro de UVM: registra la clase en la factory

    int unsigned thr_wr;     // escrituras a THR
    int unsigned rbr_rd;     // lecturas de RBR
    bit [7:0]    last_fcr;   // último byte escrito al FCR

    // Constructor
    function new(string name = "wb_spy", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    // Cada acceso terminado que publica el monitor
    function void write(wb_item t);
      if (t.adr == UART_THR && t.we)  thr_wr++;
      if (t.adr == UART_RBR && !t.we) rbr_rd++;
      if (t.adr == UART_FCR && t.we)  last_fcr = uart_lane8(t.sel, t.dat);
    endfunction

    function void clear();
      thr_wr = 0;
      rbr_rd = 0;
    endfunction
  endclass : wb_spy

  // Sumidero del agente serie: toma cada ser_item y lo guarda
  class ser_sink extends uvm_component;
    `uvm_component_utils(ser_sink)   // macro de UVM: registra la clase en la factory

    uvm_seq_item_pull_port #(ser_item) seq_item_port;
    ser_item items[$];   // lo recibido, en orden

    // Constructor
    function new(string name = "ser_sink", uvm_component parent = null);
      super.new(name, parent);
      seq_item_port = new("seq_item_port", this);
    endfunction

    task run_phase(uvm_phase phase);
      ser_item it;
      forever begin
        seq_item_port.get_next_item(it);
        items.push_back(it);
        seq_item_port.item_done();
      end
    endtask

    // Cuántos items traen ese error
    function int count_err(uart_ser_err_e e);
      int n = 0;
      foreach (items[i]) if (items[i].err == e) n++;
      return n;
    endfunction
  endclass : ser_sink

  // Sumidero del agente de módem: toma cada mdm_item y lo guarda
  class mdm_sink extends uvm_component;
    `uvm_component_utils(mdm_sink)   // macro de UVM: registra la clase en la factory

    uvm_seq_item_pull_port #(mdm_item) seq_item_port;
    mdm_item items[$];   // lo recibido, en orden

    // Constructor
    function new(string name = "mdm_sink", uvm_component parent = null);
      super.new(name, parent);
      seq_item_port = new("seq_item_port", this);
    endfunction

    task run_phase(uvm_phase phase);
      mdm_item it;
      forever begin
        seq_item_port.get_next_item(it);
        items.push_back(it);
        seq_item_port.item_done();
      end
    endtask
  endclass : mdm_sink

  // Secuencia de sw que solo hace reg_noise() 40 veces, para probarlo sin el resto de la actividad
  class sw_probe extends uart_sw_vseq;
    `uvm_object_utils(sw_probe)   // macro de UVM: registra la clase en la factory

    // Constructor
    function new(string name = "sw_probe");
      super.new(name);
    endfunction

    task body();
      repeat (40) reg_noise();
    endtask
  endclass : sw_probe

  class act_smoke_vseq extends uart_base_vseq;
    `uvm_object_utils(act_smoke_vseq)   // macro de UVM: registra la clase en la factory

    wb_spy    spy;     // los pone la prueba
    ser_sink  ssink;
    mdm_sink  msink;

    // Constructor
    function new(string name = "act_smoke_vseq");
      super.new(name);
    endfunction

    // ---------------------------------------------------------- ayudas
    // Sortea un formato (want_pen = 1 con paridad, 0 sin ella, -1 cualquiera) y fija el divisor
    function void pick_line(int dl, int want_pen = -1);
      int tries = 0;
      do begin
        if (!line().randomize()) `uvm_error("SMOKE", "no se pudo aleatorizar uart_line_cfg")
        tries++;
      end while (want_pen >= 0 && line().pen() != bit'(want_pen) && tries < 100);
      line().dl           = dl;
      line().dl_lsb_first = 0;
    endfunction

    // Sortea ctrl con loopback seguro y programa el UART con uart_program_vseq
    task run_program();
      uart_program_vseq prog = uart_program_vseq::type_id::create("prog");
      ctrl().mcr_loop_pct = 100;
      if (!ctrl().randomize()) `uvm_error("SMOKE", "no se pudo aleatorizar uart_ctrl_cfg")
      prog.start(p_sequencer);
    endtask

    // Lee DLM y DLL del DUT y los compara con line().dl
    task check_hw_divisor(string tag);
      bit [7:0] r;
      lock();
      wb_write(UART_LCR, line().lcr(1'b1), 1);
      wb_read(UART_DLM, r, 1);  act_check({tag, ": DLM del DUT = line().dl[15:8]"}, r, line().dl[15:8]);
      wb_read(UART_DLL, r, 1);  act_check({tag, ": DLL del DUT = line().dl[7:0]"},  r, line().dl[7:0]);
      wb_write(UART_LCR, line().lcr(1'b0), 1);
      unlock();
    endtask

    // Espera a que TEMT (LSR[6]) diga que el transmisor terminó
    task wait_temt();
      bit [7:0] lsr;
      bit       ok = 0;
      for (int i = 0; i < 400 && !ok; i++) begin
        wb_read(UART_LSR, lsr);
        ok = lsr[6];
        if (!ok) wait_tc(1);
      end
      act_check("TEMT llega", ok, 1);
    endtask

    // Vacía las dos FIFO con nivel de disparo 1
    task flush_fifos();
      wb_write(UART_FCR, 8'h07);
    endtask

    // ---------------------------------------------------------- A. program
    task part_a();
      bit [7:0] r;
      pick_line(1);
      run_program();
      wb_read(UART_LCR, r);  act_check("A: LCR con el formato", r, line().lcr(1'b0));
      wb_read(UART_IER, r);  act_check("A: IER (el DUT guarda [3:0])", r, ctrl().ier_byte() & 8'h0F);
      wb_read(UART_MCR, r);  act_check("A: MCR es solo escritura (AMB-02), la lectura da 0", r, 8'h00);
      act_check("A: loopback publicado al agente serie", cfg().ser.loopback, ctrl().loop);
      check_hw_divisor("A");
    endtask

    // ---------------------------------------------------------- B. tx
    task part_b();
      uart_tx_vseq tx;
      realtime     t0, dt;
      bit [7:0]    r;
      wb_write(UART_IER, 8'h00);   // sin interrupciones
      cfg().tx_gap_max = 0;

      // B1. ráfaga normal: no desborda
      cfg().tx_ovf_pct = 0;  cfg().tx_blind_pct = 0;
      flush_fifos();  spy.clear();
      tx = uart_tx_vseq::type_id::create("tx");  tx.n_bursts = 1;  tx.start(p_sequencer);
      wait_cycles(4);
      act_range("B1: ráfaga normal, escrituras a THR", spy.thr_wr, 1, 16);
      wait_temt();

      // B2. con max_len = 2 (DL lento o después de un reset)
      flush_fifos();  spy.clear();
      tx = uart_tx_vseq::type_id::create("tx");  tx.n_bursts = 3;  tx.max_len = 2;  tx.start(p_sequencer);
      wait_cycles(4);
      act_range("B2: 3 ráfagas con max_len = 2, escrituras a THR", spy.thr_wr, 3, 6);
      wait_temt();

      // B3. ráfaga que desborda, escrita a ciegas
      cfg().tx_ovf_pct = 100;  cfg().tx_blind_pct = 100;
      flush_fifos();  spy.clear();
      tx = uart_tx_vseq::type_id::create("tx");  tx.n_bursts = 1;  tx.start(p_sequencer);
      wait_cycles(4);
      act_range("B3: ráfaga que desborda a ciegas, escrituras a THR", spy.thr_wr, 17, cfg().tx_len_max);
      wait_temt();

      // B4. ráfaga larga revisando THRE: espera y no desborda
      cfg().tx_blind_pct = 0;
      flush_fifos();  spy.clear();
      tx = uart_tx_vseq::type_id::create("tx");  tx.n_bursts = 1;  tx.start(p_sequencer);
      wait_cycles(4);
      act_range("B4: ráfaga larga revisando THRE, escrituras a THR", spy.thr_wr, 17, cfg().tx_len_max);
      wait_temt();

      // B5. break: dura al menos 1 Tc y deja LCR[6] en 0
      flush_fifos();
      tx = uart_tx_vseq::type_id::create("tx");  tx.n_bursts = 0;  tx.do_break = 1;
      t0 = $realtime;
      tx.start(p_sequencer);
      dt = $realtime - t0;
      act_check("B5: el break dura al menos 1 Tc", dt >= real'(line().tc_cycles()) * UART_CLK_NS, 1);
      wb_read(UART_LCR, r);  act_check("B5: LCR sin break al terminar", r, line().lcr(1'b0));
    endtask

    // ---------------------------------------------------------- C. rx
    function void zero_ser();
      uart_ser_agent_cfg s = cfg().ser;
      s.parity_err_pct = 0;  s.frame_err_pct = 0;  s.break_pct    = 0;
      s.glitch_pct     = 0;  s.baud_in_pct   = 0;  s.baud_out_pct = 0;
      s.short_stop_pct = 0;  s.rx_gap_mode   = 0;
    endfunction

    task rx_run(int n, bit force_e = 0, bit no_e = 0);
      uart_rx_vseq rx = uart_rx_vseq::type_id::create("rx");
      ssink.items.delete();
      rx.n_chars    = n;
      rx.force_errs = force_e;
      rx.no_errs    = no_e;
      rx.start(p_sequencer);
    endtask

    task part_c();
      uart_ser_agent_cfg s = cfg().ser;
      int n = 25;
      int bad;
      int cb;   // bits de un carácter, igual que en uart_rx_vseq

      // C1. sin errores: cantidad, dirección y rangos
      zero_ser();  pick_line(1, 1);
      rx_run(n);
      act_check("C1: cantidad de caracteres", ssink.items.size(), n);
      act_check("C1: todos sin error", ssink.count_err(SER_OK), n);
      bad = 0;
      foreach (ssink.items[i])
        if (ssink.items[i].dir != SER_DIR_RX || !(ssink.items[i].glitch_w inside {[1:15]}) ||
            ssink.items[i].gap_bits > s.rx_gap_max) bad++;
      act_check("C1: dir RX, glitch_w y pausa en rango", bad, 0);

      // C2. modos de pausa: pegados y solo largas
      s.rx_gap_mode = 1;  rx_run(n);
      bad = 0;  foreach (ssink.items[i]) if (ssink.items[i].gap_bits != 0) bad++;
      act_check("C2: modo 1, todas las pausas en 0", bad, 0);
      s.rx_gap_mode = 2;  rx_run(n);
      bad = 0;  foreach (ssink.items[i]) if (ssink.items[i].gap_bits < 16 || ssink.items[i].gap_bits > s.rx_gap_max) bad++;
      act_check("C2: modo 2, todas las pausas de 16 a rx_gap_max", bad, 0);
      s.rx_gap_mode = 0;

      // C3. error de paridad solo si hay paridad
      for (int p = 0; p < 2; p++) begin
        zero_ser();  pick_line(1, p);  s.parity_err_pct = 100;
        rx_run(n);
        act_check($sformatf("C3: parity_err_pct = 100, con paridad = %0d", p),
                  ssink.count_err(p ? SER_PARITY : SER_OK), n);
      end

      // C4. trama, glitch, break y baudios
      zero_ser();  s.frame_err_pct = 100;  rx_run(n);
      act_check("C4: todos con error de trama", ssink.count_err(SER_FRAME), n);

      zero_ser();  s.glitch_pct = 100;  rx_run(n);
      act_check("C4: todos con glitch", ssink.count_err(SER_GLITCH), n);

      zero_ser();  s.break_pct = 100;  rx_run(n);
      act_check("C4: todos con break", ssink.count_err(SER_BREAK), n);
      cb  = (16 * (1 + line().data_bits() + line().pen()) + line().stop_ticks() + 15) / 16;
      bad = 0;
      foreach (ssink.items[i])
        if (ssink.items[i].break_bits < cb + 1 || ssink.items[i].break_bits > cb * (1 + s.break_extra_max) + 1) bad++;
      act_check("C4: break de 1 a 1 + break_extra_max Tc", bad, 0);

      zero_ser();  s.baud_in_pct = 100;  rx_run(n);
      act_check("C4: todos con baudios dentro de tolerancia", ssink.count_err(SER_BAUD_IN), n);
      bad = 0;
      foreach (ssink.items[i])
        if (((ssink.items[i].baud_dev < 0) ? -ssink.items[i].baud_dev : ssink.items[i].baud_dev) > s.baud_in_max ||
            ssink.items[i].baud_dev == 0) bad++;
      act_check("C4: |baud_dev| de 1 a baud_in_max", bad, 0);

      zero_ser();  s.baud_out_pct = 100;  rx_run(n);
      act_check("C4: todos con baudios fuera de tolerancia", ssink.count_err(SER_BAUD_OUT), n);
      bad = 0;
      foreach (ssink.items[i])
        if (((ssink.items[i].baud_dev < 0) ? -ssink.items[i].baud_dev : ssink.items[i].baud_dev) < s.baud_out_min ||
            ((ssink.items[i].baud_dev < 0) ? -ssink.items[i].baud_dev : ssink.items[i].baud_dev) > s.baud_out_max) bad++;
      act_check("C4: |baud_dev| de baud_out_min a baud_out_max", bad, 0);

      // C5. parada corta: solo con LCR[2] = 1; no_errs la apaga
      zero_ser();  s.short_stop_pct = 100;
      for (int k = 0; k < 2; k++) begin
        pick_line(1);
        rx_run(n);
        bad = 0;  foreach (ssink.items[i]) if (ssink.items[i].short_stop != line().stb) bad++;
        act_check($sformatf("C5: short_stop = stb (stb = %0d)", line().stb), bad, 0);
      end
      s.parity_err_pct = 100;
      rx_run(n, 0, 1);
      bad = 0;  foreach (ssink.items[i]) if (ssink.items[i].short_stop || ssink.items[i].err != SER_OK) bad++;
      act_check("C5: no_errs, sin error y sin parada corta", bad, 0);

      // C6. force_errs: primero paridad (si hay), segundo trama
      zero_ser();
      for (int p = 0; p < 2; p++) begin
        pick_line(1, p);
        rx_run(4, 1, 0);
        act_check($sformatf("C6: primer carácter (paridad = %0d)", p), ssink.items[0].err, p ? SER_PARITY : SER_OK);
        act_check($sformatf("C6: segundo carácter con trama (paridad = %0d)", p), ssink.items[1].err, SER_FRAME);
      end
      zero_ser();
    endtask

    // ---------------------------------------------------------- D. mdm
    task mdm_run(int n);
      uart_mdm_vseq mdm = uart_mdm_vseq::type_id::create("mdm");
      msink.items.delete();
      mdm.n_changes = n;
      mdm.start(p_sequencer);
    endtask

    task part_d();
      modem_agent_cfg  m  = cfg().mdm;
      int              n  = 20;
      int              bad;
      longint unsigned tc = line().tc_cycles();

      // D1. una sola señal (RI), sin cambios dobles
      m.sig_w = '{0, 0, 1, 0};  m.multi_pct = 0;
      mdm_run(n);
      act_check("D1: cantidad de cambios", msink.items.size(), n);
      bad = 0;  foreach (msink.items[i]) if (msink.items[i].toggle != 4'b0100) bad++;
      act_check("D1: siempre solo RI", bad, 0);
      bad = 0;  foreach (msink.items[i]) if (msink.items[i].gap_cycles % tc != 0 || msink.items[i].gap_cycles > m.gap_max * tc) bad++;
      act_check("D1: pausa en Tc enteros, hasta gap_max Tc", bad, 0);

      // D2. siempre dos señales a la vez
      m.sig_w = '{1, 1, 1, 1};  m.multi_pct = 100;
      mdm_run(n);
      bad = 0;  foreach (msink.items[i]) if ($countones(msink.items[i].toggle) != 2) bad++;
      act_check("D2: siempre dos señales", bad, 0);

      // D3. solo DCD
      m.sig_w = '{0, 0, 0, 1};  m.multi_pct = 0;
      mdm_run(n);
      bad = 0;  foreach (msink.items[i]) if (msink.items[i].toggle != 4'b1000) bad++;
      act_check("D3: siempre solo DCD", bad, 0);
    endtask

    // ---------------------------------------------------------- E. sw
    // Manda 4 caracteres por loopback mientras sw atiende en el modo pedido
    task run_sw(uart_sw_mode_e m);
      uart_sw_vseq sw = uart_sw_vseq::type_id::create("sw");
      bit [7:0]    r;
      bit          saw = 0;
      sw.mode = m;
      flush_fifos();
      spy.clear();
      p_sequencer.traffic_done = 0;
      fork : irqw
        begin wait (p_sequencer.cfg.wb.vif.irq === 1'b1);  saw = 1; end
      join_none
      fork
        sw.start(p_sequencer);
        begin
          repeat (4) wb_write(UART_THR, 8'h30 + $urandom_range(9));
          wait_tc(12);
          p_sequencer.traffic_done = 1;
        end
      join
      disable irqw;
      wait_cycles(8);
      wb_read(UART_LSR, r);
      act_check({m.name(), ": FIFO RX vacía (DR = 0)"}, r[0], 0);
      act_check({m.name(), ": al menos 4 lecturas de RBR"}, spy.rbr_rd >= 4, 1);
      act_check({m.name(), ": int_o subió solo en el modo de interrupciones"}, saw, (m == SW_IRQ));
      p_sequencer.traffic_done = 0;
    endtask

    task part_e();
      sw_probe probe;
      bit      sem_ok;
      cfg().sw_delay_min = 0;  cfg().sw_delay_max = 1;   // atiende rápido, el humo no espera 24 Tc
      cfg().sw_partial_pct = 0;  cfg().sw_lsr_first_pct = 100;  cfg().reg_noise_pct = 0;

      // E1. sondeo (IER = 0) y E2. interrupciones (IER = RDA)
      wb_write(UART_IER, 8'h00);
      run_sw(SW_POLL);
      wb_write(UART_IER, 8'h01);
      run_sw(SW_IRQ);
      wb_write(UART_IER, 8'h00);

      // E3. reg_noise con DLAB = 1 y con DLAB = 0: el bus queda libre y LCR y divisor intactos
      for (int k = 0; k < 2; k++) begin
        bit [7:0] r;
        cfg().reg_dlab_pct = k ? 0 : 100;
        probe = sw_probe::type_id::create("probe");
        probe.start(p_sequencer);
        sem_ok = p_sequencer.bus_sem.try_get(1);
        if (sem_ok) p_sequencer.bus_sem.put(1);
        act_check($sformatf("E3: bus libre tras reg_noise (reg_dlab_pct = %0d)", cfg().reg_dlab_pct), sem_ok, 1);
        wb_read(UART_LCR, r);
        act_check($sformatf("E3: LCR intacto, DLAB = 0 (reg_dlab_pct = %0d)", cfg().reg_dlab_pct), r, line().lcr(1'b0));
        check_hw_divisor($sformatf("E3 (reg_dlab_pct = %0d)", cfg().reg_dlab_pct));
      end
      wb_write(UART_IER, 8'h00);
    endtask

    // ---------------------------------------------------------- F. events
    task part_f();
      uart_events_vseq ev;
      virtual wb_if    vif = cfg().wb.vif;
      realtime         t_rise, t_fall, dur;
      bit [7:0]        r, f;

      // F1. reconfig: LCR y divisor del DUT siguen a line() después de cada evento
      pick_line(1);  run_program();
      for (int i = 0; i < 16; i++) begin
        ev = uart_events_vseq::type_id::create("ev");
        ev.do_reconfig = 1;  ev.window_tc = 1;
        ev.start(p_sequencer);
        wb_read(UART_LCR, r);
        act_check($sformatf("F1.%0d: LCR del DUT = line()", i), r, line().lcr(1'b0));
        check_hw_divisor($sformatf("F1.%0d", i));
      end

      // F2. fifo_clear: el FCR limpia, conserva el nivel de disparo y la FIFO RX queda vacía si se pidió
      pick_line(1);  run_program();
      wb_write(UART_IER, 8'h00);
      for (int i = 0; i < 8; i++) begin
        wb_write(UART_FCR, {ctrl().tl, 6'b000111});
        repeat (2) wb_write(UART_THR, 8'h41 + i);
        wait_tc(6);
        wb_read(UART_LSR, r);
        act_check($sformatf("F2.%0d: antes de limpiar hay dato en RX", i), r[0], 1);
        ev = uart_events_vseq::type_id::create("ev");
        ev.do_fifo_clr = 1;  ev.window_tc = 1;
        ev.start(p_sequencer);
        wait_cycles(4);
        f = spy.last_fcr;
        act_check($sformatf("F2.%0d: FCR limpia RX, TX o las dos", i), f[2:1] != 0, 1);
        act_check($sformatf("F2.%0d: FCR conserva el nivel de disparo", i), f[7:6], ctrl().tl);
        if (f[1]) begin
          wb_read(UART_LSR, r);
          act_check($sformatf("F2.%0d: FIFO RX vacía tras limpiar", i), r[0], 0);
        end
      end

      // F3. reset: dura entre 1 ns y rst_width_max ciclos, sube rst_hit y el DUT vuelve a sus valores de reset
      ev = uart_events_vseq::type_id::create("ev");
      ev.do_reset = 1;  ev.window_tc = 0;
      fork : rw
        begin @(posedge vif.rst);  t_rise = $realtime;  @(negedge vif.rst);  t_fall = $realtime; end
      join_none
      ev.start(p_sequencer);
      wait_cycles(4);
      disable rw;
      dur = t_fall - t_rise;
      act_check("F3: el reset dura entre 1 ns y rst_width_max ciclos más 20 ns",
                (dur >= 1.0) && (dur <= cfg().rst_width_max * UART_CLK_NS + 20.0), 1);
      act_check("F3: rst_hit arriba", p_sequencer.rst_hit, 1);
      p_sequencer.rst_hit = 0;
      wb_read(UART_LCR, r);  act_check("F3: LCR en su valor de reset", r, 8'h03);
      wb_read(UART_IER, r);  act_check("F3: IER en su valor de reset", r, 8'h00);
      wb_read(UART_MCR, r);  act_check("F3: MCR en su valor de reset", r, 8'h00);
    endtask

    task body();
      part_a();
      part_b();
      part_c();
      part_d();
      part_e();
      part_f();
    endtask
  endclass : act_smoke_vseq

  // Env mínimo: agente Wishbone, dos sumideros, el espía y el secuenciador virtual
  class act_smoke_env extends uvm_env;
    `uvm_component_utils(act_smoke_env)   // macro de UVM: registra la clase en la factory
    uart_wb_agent             wb_agt;    // agente Wishbone
    uvm_sequencer #(ser_item) ser_sqr;   // secuenciador que atiende el sumidero serie
    uvm_sequencer #(mdm_item) mdm_sqr;   // secuenciador que atiende el sumidero de módem
    ser_sink                  ssink;
    mdm_sink                  msink;
    wb_spy                    spy;
    uart_virtual_sequencer    vsqr;      // donde corre la secuencia

    // Constructor
    function new(string name = "env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    // Crea todo con la factory
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      wb_agt  = uart_wb_agent::type_id::create("wb_agt", this);
      ser_sqr = uvm_sequencer #(ser_item)::type_id::create("ser_sqr", this);
      mdm_sqr = uvm_sequencer #(mdm_item)::type_id::create("mdm_sqr", this);
      ssink   = ser_sink::type_id::create("ssink", this);
      msink   = mdm_sink::type_id::create("msink", this);
      spy     = wb_spy::type_id::create("spy", this);
      vsqr    = uart_virtual_sequencer::type_id::create("vsqr", this);
    endfunction

    // Conecta los sumideros a sus secuenciadores y el espía al monitor Wishbone
    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      vsqr.wb_sqr  = wb_agt.sqr;
      vsqr.ser_sqr = ser_sqr;
      vsqr.mdm_sqr = mdm_sqr;
      ssink.seq_item_port.connect(ser_sqr.seq_item_export);
      msink.seq_item_port.connect(mdm_sqr.seq_item_export);
      wb_agt.ap.connect(spy.analysis_export);
    endfunction
  endclass : act_smoke_env

  // Prueba
  class uart_act_smoke_test extends uvm_test;
    `uvm_component_utils(uart_act_smoke_test)   // macro de UVM: registra la clase en la factory

    uart_env_cfg  cfg;      // configuración de la corrida
    act_smoke_env env;      // env mínimo
    virtual wb_if wb_vif;   // interfaz virtual (la publica tb_top)

    // Constructor
    function new(string name = "uart_act_smoke_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    // Crea la configuración, la publica y crea el env
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual wb_if)::get(this, "", UART_KEY_WB_VIF, wb_vif))
        `uvm_fatal("NOVIF", "No se encontró wb_vif en uvm_config_db")

      cfg = uart_env_cfg::type_id::create("cfg");   // crea el objeto con la factory
      cfg.parse_plusargs();
      cfg.wb.vif = wb_vif;
      uvm_config_db#(uart_env_cfg)::set (this, "env*",        "env_cfg",   cfg);
      uvm_config_db#(wb_agent_cfg)::set (this, "env.wb_agt*", UART_KEY_CFG, cfg.wb);

      env = act_smoke_env::type_id::create("env", this);   // crea el objeto con la factory
    endfunction

    task run_phase(uvm_phase phase);
      act_smoke_vseq seq = act_smoke_vseq::type_id::create("seq");   // crea el objeto con la factory

      phase.raise_objection(this);   // mantiene la prueba viva

      // Espera el reset inicial
      @(posedge wb_vif.clk);
      wait (wb_vif.rst === 1'b0);
      repeat (3) @(posedge wb_vif.clk);

      seq.spy   = env.spy;
      seq.ssink = env.ssink;
      seq.msink = env.msink;
      seq.start(env.vsqr);
      repeat (5) @(posedge wb_vif.clk);

      phase.drop_objection(this);   // termina la prueba
    endtask

    // Resultado final
    function void report_phase(uvm_phase phase);
      uvm_report_server srv = uvm_report_server::get_server();
      if (srv.get_severity_count(UVM_ERROR) == 0 && srv.get_severity_count(UVM_FATAL) == 0)
        `uvm_info("SMOKE", "RESULTADO: PASA", UVM_NONE)
      else
        `uvm_info("SMOKE", "RESULTADO: FALLA", UVM_NONE)
    endfunction
  endclass : uart_act_smoke_test

endpackage : uart_act_smoke_pkg
