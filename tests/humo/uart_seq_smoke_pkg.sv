//////////////////////////////////////////////////////////////////////////////////
// uart_seq_smoke_pkg.sv
// Prueba de humo de uart_base_vseq (fase F3), con el agente Wishbone y el DUT pero sin
// serie, módem, scoreboard ni cobertura, solo para ver si el acceso al bus y el semáforo funcionan
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

package uart_seq_smoke_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import uart_pkg::*;   // clases del ambiente y constantes UART_* de uart_types.sv

  // Compara un valor con el esperado
  function automatic void vseq_check(string what, longint got, longint exp);
    if (got !== exp)
      `uvm_error("SMOKE", $sformatf("%s: obtuvo 0x%0h, esperaba 0x%0h", what, got, exp))
    else
      `uvm_info("SMOKE", $sformatf("%s = 0x%0h OK", what, got), UVM_LOW)
  endfunction

  class base_smoke_vseq extends uart_base_vseq;
    `uvm_object_utils(base_smoke_vseq)   // macro de UVM: registra la clase en la factory

    // Constructor
    function new(string name = "base_smoke_vseq");
      super.new(name);
    endfunction

    task body();   // cuerpo de la secuencia
      bit [7:0]    r, ra, rb;   // datos leídos
      int unsigned n0 = 0, n100 = 0;   // sorteos de pct(0) y pct(100) que salieron mal
      bit          visto[2];   // índices que salieron de pick_w
      int unsigned w0[] = '{0, 0, 5};   // pesos con un solo índice posible
      int unsigned w1[] = '{1, 1};      // pesos iguales

      // A. lock() toma el semáforo y unlock() lo libera
      lock();
      vseq_check("semáforo tomado (try_get falla)", p_sequencer.bus_sem.try_get(1), 0);
      unlock();
      vseq_check("semáforo libre (try_get funciona)", p_sequencer.bus_sem.try_get(1), 1);
      p_sequencer.bus_sem.put(1);   // devuelve la llave que tomó la prueba

      // B. scratch con y sin el candado ya tomado (held)
      wb_write(UART_SCR, 8'hA5);  wb_read(UART_SCR, r);  vseq_check("scratch A5", r, 8'hA5);
      wb_write(UART_SCR, 8'h5A);  wb_read(UART_SCR, r);  vseq_check("scratch 5A", r, 8'h5A);
      lock();
      wb_write(UART_SCR, 8'hFF, 1);  wb_read(UART_SCR, r, 1);  vseq_check("scratch FF con held", r, 8'hFF);
      unlock();
      vseq_check("semáforo libre tras los accesos", p_sequencer.bus_sem.try_get(1), 1);
      p_sequencer.bus_sem.put(1);

      // C. dos hilos con ventana propia: sin el semáforo uno leería el valor del otro
      fork
        begin lock();  wb_write(UART_SCR, 8'h11, 1);  wb_read(UART_SCR, ra, 1);  unlock(); end
        begin lock();  wb_write(UART_SCR, 8'h22, 1);  wb_read(UART_SCR, rb, 1);  unlock(); end
      join
      vseq_check("hilo 1 leyó lo que escribió", ra, 8'h11);
      vseq_check("hilo 2 leyó lo que escribió", rb, 8'h22);

      // D. write_divisor() en los dos órdenes: DLM y DLL se leen con DLAB = 1 y LCR queda con el formato
      if (!line().randomize()) `uvm_error("SMOKE", "no se pudo aleatorizar uart_line_cfg")
      for (int orden = 0; orden < 2; orden++) begin
        line().dl_lsb_first = orden;
        `uvm_info("SMOKE", $sformatf("divisor: %s", line().convert2string()), UVM_LOW)
        write_divisor();
        lock();
        wb_write(UART_LCR, line().lcr(1'b1), 1);
        wb_read(UART_DLM, r, 1);  vseq_check($sformatf("DLM (DLL primero = %0d)", orden), r, line().dl[15:8]);
        wb_read(UART_DLL, r, 1);  vseq_check($sformatf("DLL (DLL primero = %0d)", orden), r, line().dl[7:0]);
        wb_write(UART_LCR, line().lcr(1'b0), 1);
        wb_read(UART_LCR, r, 1);  vseq_check($sformatf("LCR con el formato (DLL primero = %0d)", orden), r, line().lcr(1'b0));
        unlock();
      end

      // E. sorteos: pct() en los extremos y pick_w() con pesos
      repeat (200) begin
        if (pct(0))    n0++;
        if (!pct(100)) n100++;
        visto[pick_w(w1)] = 1;
        if (pick_w(w0) != 2) `uvm_error("SMOKE", "pick_w eligió un índice con peso 0")
      end
      vseq_check("pct(0) verdadero", n0, 0);
      vseq_check("pct(100) falso", n100, 0);
      vseq_check("pick_w con pesos iguales: índices distintos", visto[0] + visto[1], 2);
    endtask
  endclass : base_smoke_vseq

  // Env mínimo: agente Wishbone y secuenciador virtual
  class seq_smoke_env extends uvm_env;
    `uvm_component_utils(seq_smoke_env)   // macro de UVM: registra la clase en la factory
    uart_wb_agent          wb_agt;   // agente Wishbone
    uart_virtual_sequencer vsqr;     // donde corre la secuencia

    // Constructor
    function new(string name = "env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    // Crea el agente y el secuenciador virtual
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      wb_agt = uart_wb_agent::type_id::create("wb_agt", this);   // crea el objeto con la factory
      vsqr   = uart_virtual_sequencer::type_id::create("vsqr", this);
    endfunction

    // El secuenciador virtual solo necesita el de Wishbone
    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      vsqr.wb_sqr = wb_agt.sqr;
    endfunction
  endclass : seq_smoke_env

  // Prueba
  class uart_seq_smoke_test extends uvm_test;
    `uvm_component_utils(uart_seq_smoke_test)   // macro de UVM: registra la clase en la factory

    uart_env_cfg  cfg;      // configuración de la corrida
    seq_smoke_env env;      // env mínimo
    virtual wb_if wb_vif;   // interfaz virtual (la publica tb_top)

    // Constructor
    function new(string name = "uart_seq_smoke_test", uvm_component parent = null);
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

      env = seq_smoke_env::type_id::create("env", this);   // crea el objeto con la factory
    endfunction

    task run_phase(uvm_phase phase);
      base_smoke_vseq seq = base_smoke_vseq::type_id::create("seq");   // crea el objeto con la factory

      phase.raise_objection(this);   // mantiene la prueba viva

      // Espera el reset inicial
      @(posedge wb_vif.clk);
      wait (wb_vif.rst === 1'b0);
      repeat (3) @(posedge wb_vif.clk);

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
  endclass : uart_seq_smoke_test

endpackage : uart_seq_smoke_pkg
