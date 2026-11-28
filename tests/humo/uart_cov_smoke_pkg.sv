//////////////////////////////////////////////////////////////////////////////////
// uart_cov_smoke_pkg.sv
// Prueba de humo de uart_cov (fase F7), sin DUT: se le entregan accesos Wishbone, caracteres,
// cambios de módem, flancos de int_o y eventos del modelo armados a mano, y se revisa que cada
// covergroup suba, que las copias de DLAB e IER sigan al bus y que salga [COV_CURVE] por episodio.
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

package uart_cov_smoke_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import uart_pkg::*;             // uart_cov, items y constantes UART_* del ambiente

  // Compara un valor con el esperado
  function automatic void cov_check(string what, longint got, longint exp);
    if (got !== exp)
      `uvm_error("SMOKE", $sformatf("%s: obtuvo 0x%0h, esperaba 0x%0h", what, got, exp))
    else
      `uvm_info("SMOKE", $sformatf("%s = 0x%0h OK", what, got), UVM_LOW)
  endfunction

  // Revisa que la cobertura haya subido
  function automatic void cov_up(string what, real antes, real despues);
    cov_check({what, ": la cobertura sube"}, despues > antes, 1);
  endfunction

  // Revisa que la cobertura no se haya movido
  function automatic void cov_same(string what, real antes, real despues);
    cov_check({what, ": la cobertura no se mueve"}, despues == antes, 1);
  endfunction

  // Prueba
  class uart_cov_smoke_test extends uvm_test;
    `uvm_component_utils(uart_cov_smoke_test)   // macro de UVM: registra la clase en la factory

    uart_cov_cfg  cfg;   // configuración de la cobertura
    uart_cov      cov;   // lo que se prueba

    // Constructor
    function new(string name = "uart_cov_smoke_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    // Crea la configuración, la publica y crea la cobertura
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      cfg      = uart_cov_cfg::type_id::create("cfg");   // crea el objeto con la factory
      cfg.line = uart_line_cfg::type_id::create("line");
      cfg.ctrl = uart_ctrl_cfg::type_id::create("ctrl");
      cfg.line.wls = 2'd3;  cfg.line.stb = 1;  cfg.line.par_mode = PAR_ODD;  cfg.line.dl = 16'd3;
      cfg.ctrl.loop = 0;    cfg.ctrl.tl = 2'd0;
      uvm_config_db#(uart_cov_cfg)::set(this, "cov", "cfg", cfg);
      cov = uart_cov::type_id::create("cov", this);   // crea el objeto con la factory
    endfunction

    // ---------------------------------------------------------- ayudas
    // Un acceso Wishbone al registro reg, con el dato en el carril que le toca
    function wb_item acc(int reg_n, bit we, bit [7:0] b);
      wb_item it = wb_item::type_id::create("it");
      it.adr = reg_n;
      it.we  = we;
      if (reg_n >= 8) begin
        it.sel = 4'b1111;
        it.dat = {24'h0, b};
      end else begin
        it.sel = 4'b1000 >> reg_n[1:0];
        it.dat = '0;
        case (reg_n % 4)
          0: it.dat[31:24] = b;
          1: it.dat[23:16] = b;
          2: it.dat[15:8]  = b;
          3: it.dat[7:0]   = b;
        endcase
      end
      if (!we) it.dat_rd = it.dat;   // la lectura trae el dato en el mismo carril
      return it;
    endfunction

    // Un carácter de serie
    function ser_item chr(bit [7:0] d, uart_ser_err_e e);
      ser_item s = ser_item::type_id::create("s");
      s.data = d;
      s.err  = e;
      return s;
    endfunction

    // Un evento del modelo
    function uart_model_evt evt(uart_evt_e k, int unsigned txl = 0, int unsigned rxl = 0,
                                bit tb = 0, bit rb = 0, int unsigned rc = 0);
      uart_model_evt e = uart_model_evt::type_id::create("e");
      e.kind = k;  e.tx_level = txl;  e.rx_level = rxl;
      e.tx_busy = tb;  e.rx_busy = rb;  e.rst_cycles = rc;
      return e;
    endfunction

    // ---------------------------------------------------------- casos
    // H1. el grupo del formato sube con TX y RX, y no con un error de RX ni con un break
    task case_line();
      real a, b;
      int n_cov, n_tot;   // get_coverage pide int
      ser_item brk = chr(8'h00, SER_BREAK);
      a = cov.cg_line_cfg.get_coverage();
      cov.write_tx(chr(8'h55, SER_OK));
      b = cov.cg_line_cfg.get_coverage();
      cov_up("H1 TX completo en cg_line_cfg", a, b);
      a = b;
      cov.write_rx(chr(8'hAA, SER_OK));
      b = cov.cg_line_cfg.get_coverage();
      cov_up("H1 RX completo en cg_line_cfg", a, b);
      a = b;
      cov.write_rx(chr(8'h11, SER_PARITY));
      b = cov.cg_line_cfg.get_coverage();
      cov_same("H1 RX con error de paridad en cg_line_cfg", a, b);
      a = cov.cg_tx.get_coverage();
      cov.write_tx(brk);
      b = cov.cg_tx.get_coverage();
      cov_up("H1 break de TX en cg_tx", a, b);
      void'(cov.cg_line_cfg.cp_dl_band.get_coverage(n_cov, n_tot));
      cov_check("H1 cp_dl_band tiene 5 bandas", n_tot, 5);
    endtask

    // H2. DLAB, divisor e IER siguen las escrituras del bus
    task case_bus();
      real a, b;
      a = cov.cg_reg_access.get_coverage();
      cov.write_wb(acc(UART_LCR, 1, 8'h83));
      b = cov.cg_reg_access.get_coverage();
      cov_up("H2 escritura de LCR en cg_reg_access", a, b);
      cov_check("H2 DLAB abierto", cov.dlab, 1);
      a = cov.cg_dl.get_coverage();
      cov.write_wb(acc(UART_DLL, 1, 8'h03));
      b = cov.cg_dl.get_coverage();
      cov_same("H2 solo DLL en cg_dl", a, b);
      cov.write_wb(acc(UART_DLM, 1, 8'h00));
      b = cov.cg_dl.get_coverage();
      cov_up("H2 DLL y DLM en cg_dl", a, b);
      a = cov.cg_err.get_coverage();
      cov.write_wb(acc(UART_LSR, 0, 8'h60));
      b = cov.cg_err.get_coverage();
      cov_up("H2 lectura de LSR con DLAB = 1 en cg_err", a, b);
      cov.write_wb(acc(UART_LCR, 1, 8'h03));
      cov_check("H2 DLAB cerrado", cov.dlab, 0);
      cov.write_wb(acc(UART_IER, 1, 8'h0A));
      cov_check("H2 IER con DLAB = 0", cov.ier, 4'hA);
      cov.write_wb(acc(UART_LCR, 1, 8'h83));
      cov.write_wb(acc(UART_DLM, 1, 8'h05));
      cov_check("H2 DLM con DLAB = 1 no toca IER", cov.ier, 4'hA);
      cov.write_wb(acc(UART_LCR, 1, 8'h03));
    endtask

    // H3. lecturas de LSR, IIR y MSR, y escrituras de MCR y FCR
    task case_regs();
      real a, b;
      wb_item bad = acc(UART_LSR, 0, 8'h60);
      bad.sel = 4'b0000;
      a = cov.cg_err.get_coverage();
      cov.write_wb(bad);
      b = cov.cg_err.get_coverage();
      cov_same("H3 lectura de LSR con sel inválido", a, b);
      a = cov.cg_int.get_coverage();
      cov.write_wb(acc(UART_IIR, 0, 8'h01));
      b = cov.cg_int.get_coverage();
      cov_up("H3 lectura de IIR en cg_int", a, b);
      a = cov.cg_modem.get_coverage();
      cov.write_wb(acc(UART_MSR, 0, 8'h04));
      b = cov.cg_modem.get_coverage();
      cov_up("H3 lectura de MSR en cg_modem", a, b);
      a = b;
      cov.write_wb(acc(UART_MCR, 1, 8'h13));
      b = cov.cg_modem.get_coverage();
      cov_up("H3 escritura de MCR en cg_modem", a, b);
      a = cov.cg_fifo_ctrl.get_coverage();
      b = cov.cg_reconfig.get_coverage();
      cov.write_wb(acc(UART_FCR, 1, 8'h02));
      cov_up("H3 FCR sin tráfico en cg_fifo_ctrl", a, cov.cg_fifo_ctrl.get_coverage());
      cov_same("H3 FCR sin tráfico en cg_reconfig", b, cov.cg_reconfig.get_coverage());
    endtask

    // H4. eventos del modelo: niveles de FIFO, tráfico y reset
    task case_evt();
      real a, b;
      a = cov.cg_tx.get_coverage();
      cov.write_evt(evt(EV_THR_WRITE, 15, 0, 1, 0));
      b = cov.cg_tx.get_coverage();
      cov_up("H4 escritura a THR en cg_tx", a, b);
      cov_check("H4 tráfico TX activo", cov.traffic(), 1);
      a = cov.cg_fifo_ctrl.get_coverage();
      b = cov.cg_reconfig.get_coverage();
      cov.write_wb(acc(UART_FCR, 1, 8'hC2));
      cov_up("H4 FCR con tráfico en cg_fifo_ctrl", a, cov.cg_fifo_ctrl.get_coverage());
      cov_up("H4 FCR con tráfico en cg_reconfig", b, cov.cg_reconfig.get_coverage());
      a = cov.cg_rx.get_coverage();
      cov.write_evt(evt(EV_RX_PUSH, 0, 0));
      b = cov.cg_rx.get_coverage();
      cov_up("H4 push a la FIFO RX en cg_rx", a, b);
      a = b;
      cov.write_evt(evt(EV_RBR_READ, 0, 0));
      b = cov.cg_rx.get_coverage();
      cov_up("H4 lectura de RBR con la FIFO vacía en cg_rx", a, b);
      cov.dlab = 1;  cov.ier = 4'h5;
      a = cov.cg_reset.get_coverage();
      cov.write_evt(evt(EV_RESET, 0, 0, 0, 0, 2));
      b = cov.cg_reset.get_coverage();
      cov_up("H4 reset en cg_reset", a, b);
      cov_check("H4 el reset limpia DLAB", cov.dlab, 0);
      cov_check("H4 el reset limpia IER", cov.ier, 0);
    endtask

    // H5. módem e interrupción
    task case_mdm_int();
      real a, b;
      mdm_item m = mdm_item::type_id::create("m");
      uart_int_item i = uart_int_item::type_id::create("i");
      m.in_chg = 4'b0100;  m.in_val = 4'b0100;
      a = cov.cg_modem.get_coverage();
      cov.write_mdm(m);
      b = cov.cg_modem.get_coverage();
      cov_up("H5 cambio de RI en cg_modem", a, b);
      cov_check("H5 RI subió", cov.last_ri_rise, 1);
      i.level = 1;
      a = cov.cg_int.get_coverage();
      cov.write_int(i);
      b = cov.cg_int.get_coverage();
      cov_up("H5 flanco de int_o en cg_int", a, b);
    endtask

    // H6. con la cobertura apagada no se muestrea nada
    task case_off();
      real a, b;
      cfg.enable = 0;
      a = cov.cg_line_cfg.get_coverage();
      cov.write_tx(chr(8'h00, SER_OK));
      b = cov.cg_line_cfg.get_coverage();
      cov_same("H6 enable = 0", a, b);
      cfg.enable = 1;
    endtask

    // H7. [COV_CURVE] una vez por episodio
    task case_curve();
      uvm_event         ev = uvm_event_pool::get_global("uart_ep_end");
      uvm_report_server rs = uvm_report_server::get_server();
      int unsigned      c0 = rs.get_id_count("COV_CURVE");
      #10;
      ev.trigger();
      #10;
      ev.trigger();
      #10;
      cov_check("H7 [COV_CURVE] por episodio", rs.get_id_count("COV_CURVE") - c0, 2);
    endtask

    task run_phase(uvm_phase phase);
      real t0, t1;
      phase.raise_objection(this);   // mantiene la prueba viva
      #1;
      t0 = cov.total();
      cov_check("H0 la cobertura total empieza en 0", t0 == 0.0, 1);
      case_line();
      case_bus();
      case_regs();
      case_evt();
      case_mdm_int();
      case_off();
      case_curve();
      t1 = cov.total();
      cov_up("H8 total", t0, t1);
      cov_check("H8 total entre 0 y 100", (t1 > 0.0) && (t1 <= 100.0), 1);
      phase.drop_objection(this);   // termina la prueba
    endtask

    // Resultado final
    function void report_phase(uvm_phase phase);
      uvm_report_server srv = uvm_report_server::get_server();
      cov_check("H9 línea de cobertura total impresa", srv.get_id_count("COV"), 1);
      if (srv.get_severity_count(UVM_ERROR) == 0 && srv.get_severity_count(UVM_FATAL) == 0)
        `uvm_info("SMOKE", "RESULTADO: PASA", UVM_NONE)
      else
        `uvm_info("SMOKE", "RESULTADO: FALLA", UVM_NONE)
    endfunction
  endclass : uart_cov_smoke_test

endpackage : uart_cov_smoke_pkg
