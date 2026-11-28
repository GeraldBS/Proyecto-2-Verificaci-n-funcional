//////////////////////////////////////////////////////////////////////////////////
// uart_main_smoke_pkg.sv
// Prueba de humo de uart_main_vseq (fase F5), con el DUT, el agente Wishbone y dos sumideros
// que hacen de agentes serie y de módem, sin depender de otro humo. Corre episodios completos:
// base, DL lento, barrido de formatos, reset en cada episodio y timeout, y revisa que cierren
// y que el DUT quede igual que line().
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

package uart_main_smoke_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import uart_pkg::*;             // clases del ambiente y constantes UART_* de uart_types.sv

  // Compara un valor con el esperado
  function automatic void main_check(string what, longint got, longint exp);
    if (got !== exp)
      `uvm_error("SMOKE", $sformatf("%s: obtuvo 0x%0h, esperaba 0x%0h", what, got, exp))
    else
      `uvm_info("SMOKE", $sformatf("%s = 0x%0h OK", what, got), UVM_LOW)
  endfunction

  // Espía de Wishbone: cuenta escrituras a THR (con DLAB = 0) y lecturas de RBR y guarda la última escritura a FCR
  class main_wb_spy extends uvm_subscriber #(wb_item);
    `uvm_component_utils(main_wb_spy)   // macro de UVM: registra la clase en la factory

    int unsigned thr_wr;     // escrituras a THR
    int unsigned rbr_rd;     // lecturas de RBR
    bit [7:0]    last_fcr;   // último byte escrito al FCR
    bit          dlab;       // copia de LCR[7] según las escrituras vistas

    // Constructor
    function new(string name = "main_wb_spy", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    // Cada acceso terminado que publica el monitor
    function void write(wb_item t);
      if (t.adr == UART_LCR && t.we)  dlab = uart_lane8(t.sel, t.dat) >> 7;
      if (t.adr == UART_THR && t.we && !dlab) thr_wr++;   // con DLAB = 1 la dirección 0 es DLL
      if (t.adr == UART_RBR && !t.we) rbr_rd++;
      if (t.adr == UART_FCR && t.we)  last_fcr = uart_lane8(t.sel, t.dat);
    endfunction

    function void clear();
      thr_wr = 0;
      rbr_rd = 0;
    endfunction
  endclass : main_wb_spy

  // Sumidero del agente serie: toma cada ser_item y lo guarda
  class main_ser_sink extends uvm_component;
    `uvm_component_utils(main_ser_sink)   // macro de UVM: registra la clase en la factory

    uvm_seq_item_pull_port #(ser_item) seq_item_port;
    ser_item items[$];   // lo recibido, en orden

    // Constructor
    function new(string name = "main_ser_sink", uvm_component parent = null);
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
  endclass : main_ser_sink

  // Sumidero del agente de módem: toma cada mdm_item y lo guarda
  class main_mdm_sink extends uvm_component;
    `uvm_component_utils(main_mdm_sink)   // macro de UVM: registra la clase en la factory

    uvm_seq_item_pull_port #(mdm_item) seq_item_port;
    mdm_item items[$];   // lo recibido, en orden

    // Constructor
    function new(string name = "main_mdm_sink", uvm_component parent = null);
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
  endclass : main_mdm_sink

  // Env mínimo: agente Wishbone, dos sumideros, el espía y el secuenciador virtual
  class main_smoke_env extends uvm_env;
    `uvm_component_utils(main_smoke_env)   // macro de UVM: registra la clase en la factory
    uart_wb_agent             wb_agt;    // agente Wishbone
    uvm_sequencer #(ser_item) ser_sqr;   // secuenciador que atiende el sumidero serie
    uvm_sequencer #(mdm_item) mdm_sqr;   // secuenciador que atiende el sumidero de módem
    main_ser_sink                  ssink;
    main_mdm_sink                  msink;
    main_wb_spy                    spy;
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
      ssink   = main_ser_sink::type_id::create("ssink", this);
      msink   = main_mdm_sink::type_id::create("msink", this);
      spy     = main_wb_spy::type_id::create("spy", this);
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
  endclass : main_smoke_env

  // Cuenta los EP_TIMEOUT y los baja a INFO para que el humo pueda provocar uno sin fallar
  class ep_timeout_catcher extends uvm_report_catcher;
    int unsigned n;   // timeouts vistos

    // Constructor
    function new(string name = "ep_timeout_catcher");
      super.new(name);
    endfunction

    function action_e catch();
      if (get_id() == "EP_TIMEOUT") begin
        n++;
        set_severity(UVM_INFO);
      end
      return THROW;
    endfunction
  endclass : ep_timeout_catcher

  class main_smoke_vseq extends uart_base_vseq;
    `uvm_object_utils(main_smoke_vseq)   // macro de UVM: registra la clase en la factory

    main_wb_spy         spy;     // los pone la prueba
    main_ser_sink       ssink;
    main_mdm_sink       msink;
    ep_timeout_catcher  touts;
    int unsigned        n_end;   // veces que se disparó uart_ep_end
    int unsigned        n_rst;   // flancos de subida de wb.rst

    // Constructor
    function new(string name = "main_smoke_vseq");
      super.new(name);
    endfunction

    // ---------------------------------------------------------- ayudas
    // Cuenta los disparos del evento que usa la cobertura al final de cada episodio
    task count_ep_end();
      uvm_event ev = uvm_event_pool::get_global("uart_ep_end");
      forever begin
        ev.wait_trigger();
        n_end++;
      end
    endtask

    // Cuenta los resets que sube el UART
    task count_resets();
      virtual wb_if vif = cfg().wb.vif;
      forever begin
        @(posedge vif.rst);
        n_rst++;
      end
    endtask

    // Valores del plan para lo que cambia cada caso, con DL chico para que corra rápido
    function void set_defaults();
      cfg().reconfig_pct     = 10;
      cfg().fifo_clr_mid_pct = 10;
      cfg().rst_pct          = 10;
      cfg().ep_timeout_tc    = 2000;
      cfg().frame_sweep      = 0;
      cfg().sw_mode          = 0;
      cfg().line.dl_min      = 1;
      cfg().line.dl_max      = 16;
      cfg().line.fmt         = -1;
    endfunction

    // LCR y divisor del DUT contra line()
    task check_hw(string tag);
      bit [7:0] r;
      wb_read(UART_LCR, r);
      main_check({tag, ": LCR del DUT = line()"}, r, line().lcr(1'b0));
      lock();
      wb_write(UART_LCR, line().lcr(1'b1), 1);
      wb_read(UART_DLM, r, 1);  main_check({tag, ": DLM del DUT = line().dl[15:8]"}, r, line().dl[15:8]);
      wb_read(UART_DLL, r, 1);  main_check({tag, ": DLL del DUT = line().dl[7:0]"},  r, line().dl[7:0]);
      wb_write(UART_LCR, line().lcr(1'b0), 1);
      unlock();
    endtask

    // Corre uart_main_vseq con n_ep episodios y revisa lo que debe cumplir cualquier corrida
    task run_main(string tag, int n_ep);
      uart_main_vseq m  = uart_main_vseq::type_id::create("main");
      int unsigned   t0 = touts.n;
      int unsigned   e0 = n_end;
      cfg().n_episodes  = n_ep;
      ssink.items.delete();
      msink.items.delete();
      spy.clear();
      m.start(p_sequencer);
      wait_cycles(2);
      main_check({tag, ": sin timeout"}, touts.n - t0, 0);
      main_check({tag, ": episodio final"}, p_sequencer.episode, n_ep);
      main_check({tag, ": uart_ep_end una vez por episodio"}, n_end - e0, n_ep);
      main_check({tag, ": rst_hit abajo al terminar"}, p_sequencer.rst_hit, 0);
      main_check({tag, ": loopback publicado = ctrl().loop"}, cfg().ser.loopback, ctrl().loop);
      main_check({tag, ": cambios de módem hasta changes_max por episodio"},
                msink.items.size() <= n_ep * cfg().mdm.changes_max, 1);
      check_hw(tag);
    endtask

    // ---------------------------------------------------------- casos
    // M1. episodios base con todo al azar (reset, reconfig y limpieza con su probabilidad)
    task case_base();
      for (int k = 0; k < 3; k++) begin
        set_defaults();
        run_main($sformatf("M1.%0d base", k), 2);
      end
    endtask

    // M2. DL = 256: poco tráfico, no más de slow_chars_max caracteres por RX
    task case_slow();
      set_defaults();
      cfg().line.dl_min = 256;  cfg().line.dl_max = 256;
      cfg().rst_pct = 0;  cfg().reconfig_pct = 0;
      run_main("M2 DL lento", 1);
      main_check("M2: DL >= slow_dl", line().dl >= cfg().ser.slow_dl, 1);
      main_check("M2: RX hasta slow_chars_max", ssink.items.size() <= cfg().ser.slow_chars_max, 1);
    endtask

    // M3. barrido de formatos con semilla 3: formatos 12 a 15, con TX, RX y un error de paridad y otro de trama
    task case_sweep();
      set_defaults();
      cfg().frame_sweep = 1;  cfg().seed = 3;
      cfg().rst_pct = 0;
      run_main("M3 barrido", 4);
      main_check("M3: último formato = 15", line().fmt, 15);
      main_check("M3: wls del formato 15", line().wls, 3);
      main_check("M3: stb del formato 15", line().stb, 1);
      main_check("M3: paridad impar del formato 15", line().par_mode == PAR_ODD, 1);
      main_check("M3: sin loopback", ctrl().loop, 0);
      main_check("M3: al menos una escritura a THR por episodio", spy.thr_wr >= 4, 1);
      main_check("M3: al menos un error de paridad por episodio", ssink.count_err(SER_PARITY) >= 4, 1);
      main_check("M3: al menos un error de trama por episodio", ssink.count_err(SER_FRAME) >= 4, 1);
    endtask

    // M4. reset en cada episodio: el UART se reprograma y queda como line()
    task case_reset();
      int unsigned r0;
      set_defaults();
      cfg().rst_pct = 100;  cfg().reconfig_pct = 0;  cfg().fifo_clr_mid_pct = 0;
      r0 = n_rst;
      run_main("M4 reset", 2);
      main_check("M4: un reset por episodio", n_rst - r0, 2);
    endtask

    // M5. timeout: con ep_timeout_tc = 0 vence al instante, avisa una vez y deja el bus libre
    task case_timeout();
      uart_main_vseq m  = uart_main_vseq::type_id::create("main_to");
      int unsigned   t0 = touts.n;
      bit            sem_ok;
      set_defaults();
      cfg().rst_pct = 0;  cfg().reconfig_pct = 0;  cfg().fifo_clr_mid_pct = 0;
      cfg().ep_timeout_tc = 0;
      cfg().n_episodes    = 1;
      m.start(p_sequencer);
      wait_cycles(2);
      main_check("M5: el timeout se avisó una vez", touts.n - t0, 1);
      sem_ok = p_sequencer.bus_sem.try_get(1);
      if (sem_ok) p_sequencer.bus_sem.put(1);
      main_check("M5: bus libre tras el timeout", sem_ok, 1);
    endtask

    task body();
      fork
        count_ep_end();
        count_resets();
      join_none
      case_base();
      case_slow();
      case_sweep();
      case_reset();
      case_timeout();
      // M6. un episodio normal después del timeout: el ambiente se recuperó
      set_defaults();
      cfg().rst_pct = 0;  cfg().reconfig_pct = 0;
      run_main("M6 tras el timeout", 1);
    endtask
  endclass : main_smoke_vseq

  // Prueba
  class uart_main_smoke_test extends uvm_test;
    `uvm_component_utils(uart_main_smoke_test)   // macro de UVM: registra la clase en la factory

    uart_env_cfg       cfg;      // configuración de la corrida
    main_smoke_env      env;      // env mínimo del humo de F4
    virtual wb_if      wb_vif;   // interfaz virtual (la publica tb_top)
    ep_timeout_catcher touts;    // cuenta los EP_TIMEOUT

    // Constructor
    function new(string name = "uart_main_smoke_test", uvm_component parent = null);
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

      env = main_smoke_env::type_id::create("env", this);   // crea el objeto con la factory
    endfunction

    task run_phase(uvm_phase phase);
      main_smoke_vseq seq = main_smoke_vseq::type_id::create("seq");   // crea el objeto con la factory

      phase.raise_objection(this);   // mantiene la prueba viva

      touts = new("touts");
      uvm_report_cb::add(null, touts);

      // Espera el reset inicial
      @(posedge wb_vif.clk);
      wait (wb_vif.rst === 1'b0);
      repeat (3) @(posedge wb_vif.clk);

      seq.spy   = env.spy;
      seq.ssink = env.ssink;
      seq.msink = env.msink;
      seq.touts = touts;
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
  endclass : uart_main_smoke_test

endpackage : uart_main_smoke_pkg
