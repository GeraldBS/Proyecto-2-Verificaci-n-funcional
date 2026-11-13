//////////////////////////////////////////////////////////////////////////////////
// uart_wb_smoke_pkg.sv
// Prueba de humo del agente Wishbone, sin el resto del ambiente, solo para ver si el desrrollo es correcto
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

package uart_wb_smoke_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import uart_pkg::*;   // clases del ambiente y constantes UART_* de uart_types.svh

  // Compara un valor leído con el esperado
  function automatic bit smoke_check(string what, bit [31:0] got, bit [31:0] exp);
    if (got !== exp) begin
      `uvm_error("SMOKE", $sformatf("%s: leyó 0x%0h, esperaba 0x%0h", what, got, exp))
      return 0;
    end
    `uvm_info("SMOKE", $sformatf("%s = 0x%0h OK", what, got), UVM_LOW)
    return 1;
  endfunction

  // Partes A y B
  class wb_smoke_seq extends wb_base_seq;
    `uvm_object_utils(wb_smoke_seq)   // macro de UVM: registra la clase en la factory

    // Constructor
    function new(string name = "wb_smoke_seq");
      super.new(name);
    endfunction

    task body();   // cuerpo de la secuencia
      bit [31:0] v;   // dato leído
      bit        ok;   // resultado de smoke_check

      // A. valores de reset
      wb_read(UART_LCR, v);  ok = smoke_check("LCR reset", v, 32'h03);
      wb_read(UART_IIR, v);  ok = smoke_check("IIR reset", v, 32'hC1);
      wb_read(UART_LSR, v);  ok = smoke_check("LSR reset", v, 32'h60);

      // A. registros de lectura y escritura
      wb_write(UART_LCR, 8'h1B);  wb_read(UART_LCR, v);  ok = smoke_check("LCR escrito", v, 32'h1B);
      wb_write(UART_SCR, 8'hA5);  wb_read(UART_SCR, v);  ok = smoke_check("scratch",     v, 32'hA5);
      wb_write(UART_IER, 8'h0F);  wb_read(UART_IER, v);  ok = smoke_check("IER",         v, 32'h0F);

      // A. DLL y DLM con DLAB = 1 (las direcciones 0 y 1 cambian de registro)
      wb_write(UART_LCR, 8'h9B);
      wb_write(UART_DLM, 8'h12);
      wb_write(UART_DLL, 8'h34);
      wb_read(UART_DLM, v);  ok = smoke_check("DLM", v, 32'h12);
      wb_read(UART_DLL, v);  ok = smoke_check("DLL", v, 32'h34);
      wb_write(UART_LCR, 8'h03);
      wb_read(UART_IER, v);  ok = smoke_check("IER con DLAB = 0", v, 32'h0F);

      // B. Debug 1 y Debug 2 (32 bits)
      wb_read(UART_DBG1, v);
      `uvm_info("SMOKE", $sformatf("Debug 1 = 0x%08h (el plan espera 0x?0031060)", v), UVM_LOW)
      wb_read(UART_DBG2, v);
      `uvm_info("SMOKE", $sformatf("Debug 2 = 0x%08h (el plan espera 0x00C00000)", v), UVM_LOW)
    endtask
  endclass : wb_smoke_seq

  // Parte C: reset con el bus en reposo
  class wb_reset_idle_seq extends wb_base_seq;
    `uvm_object_utils(wb_reset_idle_seq)   // macro de UVM: registra la clase en la factory

    // Constructor
    function new(string name = "wb_reset_idle_seq");
      super.new(name);
    endfunction

    task body();   // cuerpo de la secuencia
      bit [31:0] v;   // dato leído
      bit        ok;   // resultado de smoke_check
      wb_write(UART_LCR, 8'h1B);
      p_sequencer.async_reset(2, 7.0);       // 2 ciclos, 7 ns después de un flanco
      wb_idle(3);
      wb_read(UART_LCR, v);  ok = smoke_check("LCR tras el reset", v, 32'h03);
    endtask
  endclass : wb_reset_idle_seq

  // Parte D: ráfaga de escrituras a scratch
  class wb_burst_seq extends wb_base_seq;
    `uvm_object_utils(wb_burst_seq)   // macro de UVM: registra la clase en la factory
    int unsigned n = 20;

    // Constructor
    function new(string name = "wb_burst_seq");
      super.new(name);
    endfunction

    task body();   // cuerpo de la secuencia
      repeat (n) wb_write(UART_SCR, 8'($urandom_range(255)));
    endtask
  endclass : wb_burst_seq

  // Env mínimo
  class wb_smoke_env extends uvm_env;
    `uvm_component_utils(wb_smoke_env)   // macro de UVM: registra la clase en la factory
    uart_wb_agent wb_agt;   // agente Wishbone bajo prueba

    // Constructor
    function new(string name = "env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    // Crea el agente Wishbone
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      wb_agt = uart_wb_agent::type_id::create("wb_agt", this);   // crea el objeto con la factory
    endfunction
  endclass : wb_smoke_env

  // Prueba
  class uart_wb_smoke_test extends uvm_test;
    `uvm_component_utils(uart_wb_smoke_test)   // macro de UVM: registra la clase en la factory

    wb_agent_cfg  wb_cfg;   // configuración del agente
    wb_smoke_env  env;   // env mínimo con solo el agente Wishbone
    virtual wb_if wb_vif;   // interfaz virtual (la publica tb_top)

    uvm_tlm_analysis_fifo #(wb_item)       item_fifo;   // accesos publicados por el monitor
    uvm_tlm_analysis_fifo #(wb_rst_item)   rst_fifo;   // eventos de reset
    uvm_tlm_analysis_fifo #(uart_int_item) int_fifo;   // flancos de int_o

    // Constructor
    function new(string name = "uart_wb_smoke_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    // Crea la configuración, el env y los FIFOs que recogen lo que publica el agente
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual wb_if)::get(this, "", UART_KEY_WB_VIF, wb_vif))
        `uvm_fatal("NOVIF", "No se encontró wb_vif en uvm_config_db")

      wb_cfg = wb_agent_cfg::type_id::create("wb_cfg");   // crea el objeto con la factory
      wb_cfg.vif = wb_vif;
      wb_cfg.parse_plusargs();
      uvm_config_db#(wb_agent_cfg)::set(this, UART_PATH_WB_AGT, UART_KEY_CFG, wb_cfg);

      env       = wb_smoke_env::type_id::create("env", this);   // crea el objeto con la factory
      item_fifo = new("item_fifo", this);
      rst_fifo  = new("rst_fifo",  this);
      int_fifo  = new("int_fifo",  this);
    endfunction

    // Conecta los puertos del agente a los FIFOs
    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      env.wb_agt.ap.connect    (item_fifo.analysis_export);
      env.wb_agt.rst_ap.connect(rst_fifo.analysis_export);
      env.wb_agt.int_ap.connect(int_fifo.analysis_export);
    endfunction

    // Imprime la tabla de knobs
    function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase);
      uart_knobs::print_knobs();
    endfunction

    // Corre las partes A a E en orden
    task run_phase(uvm_phase phase);
      wb_sequencer      sqr = env.wb_agt.sqr;   // secuenciador del agente
      wb_smoke_seq      a_seq;   // partes A y B
      wb_reset_idle_seq c_seq;   // parte C
      wb_burst_seq      d_seq;   // parte D
      int unsigned      driven, seen;   // accesos del driver y accesos vistos por el monitor

      phase.raise_objection(this);   // mantiene la prueba viva

      // Espera el reset inicial
      @(posedge wb_vif.clk);
      wait (wb_vif.rst === 1'b0);
      repeat (3) @(posedge wb_vif.clk);

      // A y B
      a_seq = wb_smoke_seq::type_id::create("a_seq");   // crea el objeto con la factory
      a_seq.start(sqr);

      // C
      c_seq = wb_reset_idle_seq::type_id::create("c_seq");   // crea el objeto con la factory
      c_seq.start(sqr);

      // E (parte 1): el monitor vio todos los accesos de A, B y C
      driven = a_seq.n_acc + c_seq.n_acc;
      seen   = item_fifo.used();
      if (seen != driven)
        `uvm_error("SMOKE", $sformatf("el monitor publicó %0d accesos y el driver hizo %0d", seen, driven))
      else
        `uvm_info("SMOKE", $sformatf("monitor y driver coinciden: %0d accesos", seen), UVM_LOW)

      // D: ráfaga con un reset en medio
      d_seq = wb_burst_seq::type_id::create("d_seq");   // crea el objeto con la factory
      fork
        d_seq.start(sqr);
        begin
          repeat ($urandom_range(150, 40)) @(posedge wb_vif.clk);
          sqr.async_reset(3, 13.0);
        end
      join
      repeat (5) @(posedge wb_vif.clk);

      // E (parte 2): eventos de reset y de int_o
      check_resets();
      check_int_events();

      phase.drop_objection(this);   // termina la prueba
    endtask

    // Esperados: reset inicial, el de C (2 ciclos) y el de D (3 ciclos)
    function void check_resets();
      wb_rst_item  ev;   // evento leído del FIFO
      int unsigned starts = 0, ends = 0;   // resets que suben y que bajan
      int unsigned widths[$];   // anchos de reset medidos, en ciclos
      while (rst_fifo.try_get(ev)) begin
        `uvm_info("SMOKE", ev.convert2string(), UVM_LOW)
        if (ev.asserted) starts++;
        else begin ends++; widths.push_back(ev.width_cycles); end
      end
      if (starts != 3 || ends != 3)
        `uvm_error("SMOKE", $sformatf("eventos de reset: %0d suben y %0d bajan, esperaba 3 y 3", starts, ends))
      else if (widths[1] != 2 || widths[2] != 3)
        `uvm_error("SMOKE", $sformatf("anchos de reset medidos: %p, esperaba [_, 2, 3]", widths))
      else
        `uvm_info("SMOKE", "eventos de reset OK (inicial, 2 ciclos y 3 ciclos)", UVM_LOW)
    endfunction

    // IER = 0x0F con el transmisor vacío activa la interrupción THRE: int_o debe subir.
    function void check_int_events();
      uart_int_item item;   // flanco leído del FIFO
      int unsigned  rises = 0, falls = 0;   // flancos de subida y de bajada
      while (int_fifo.try_get(item)) begin
        `uvm_info("SMOKE", item.convert2string(), UVM_LOW)
        if (item.level) rises++; else falls++;
      end
      if (rises == 0)
        `uvm_error("SMOKE", "int_o nunca subió después de habilitar IER = 0x0F")
      else
        `uvm_info("SMOKE", $sformatf("flancos de int_o: %0d suben, %0d bajan", rises, falls), UVM_LOW)
    endfunction
  endclass : uart_wb_smoke_test

endpackage : uart_wb_smoke_pkg
