`uvm_analysis_imp_decl(_smoke_wb)
`uvm_analysis_imp_decl(_smoke_rst)
`uvm_analysis_imp_decl(_smoke_int)

class wb_smoke_sub extends uvm_component;
  `uvm_component_utils(wb_smoke_sub)

  uvm_analysis_imp_smoke_wb  #(wb_item,       wb_smoke_sub) wb_imp;
  uvm_analysis_imp_smoke_rst #(wb_rst_item,   wb_smoke_sub) rst_imp;
  uvm_analysis_imp_smoke_int #(uart_int_item, wb_smoke_sub) int_imp;

  int unsigned n_wb  = 0;
  int unsigned n_rst = 0;
  int unsigned n_int = 0;

  function new(string name = "wb_smoke_sub", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    wb_imp  = new("wb_imp",  this);
    rst_imp = new("rst_imp", this);
    int_imp = new("int_imp", this);
  endfunction

  function void write_smoke_wb(wb_item t);
    n_wb++;
    `uvm_info("SMOKE_WB", t.convert2string(), UVM_MEDIUM)
  endfunction

  function void write_smoke_rst(wb_rst_item t);
    n_rst++;
    `uvm_info("SMOKE_RST", t.convert2string(), UVM_MEDIUM)
  endfunction

  function void write_smoke_int(uart_int_item t);
    n_int++;
    `uvm_info("SMOKE_INT", t.convert2string(), UVM_MEDIUM)
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (n_wb == 0)  `uvm_error("SMOKE", "wb_monitor no capturo transacciones")
    if (n_rst < 2)  `uvm_error("SMOKE", $sformatf("se esperaban al menos 2 eventos de reset, llegaron %0d", n_rst))
    if (n_int < 2)  `uvm_error("SMOKE", $sformatf("se esperaban al menos 2 flancos de int_o, llegaron %0d", n_int))
    `uvm_info("SMOKE", $sformatf("Resumen monitores: wb=%0d rst=%0d int=%0d", n_wb, n_rst, n_int), UVM_LOW)
  endfunction
endclass : wb_smoke_sub


class wb_smoke_seq extends wb_base_seq;
  `uvm_object_utils(wb_smoke_seq)

  function new(string name = "wb_smoke_seq");
    super.new(name);
  endfunction

  task check_eq(string tag, bit [31:0] got, bit [31:0] exp, bit [31:0] mask = 32'hFFFF_FFFF);
    if ((got & mask) !== (exp & mask))
      `uvm_error("SMOKE_CHK", $sformatf("%s: leido=0x%08h esperado=0x%08h (mask=0x%08h)", tag, got, exp, mask))
  endtask

  task body();
    bit [31:0] rd;
    bit [7:0]  exp_scr = 8'h00;
    bit [7:0]  exp_lcr = 8'h03;
    bit [7:0]  exp_ier = 8'h00;
    int        reg_pick;
    bit        do_wr;
    bit [7:0]  wdata;
    int        rst_w;
    real       rst_ph;

    // 1. Valores de reset (8 bits y Debug 32 bits)
    wb_read(3,  rd); check_eq("LCR_RST",  rd, 32'h0000_0003);
    wb_read(5,  rd); check_eq("LSR_RST",  rd, 32'h0000_0060);
    wb_read(2,  rd); check_eq("IIR_RST",  rd, 32'h0000_00C1);
    wb_read(8,  rd); check_eq("DBG1_RST", rd, 32'h0003_1060, 32'h0FFF_FFFF);
    wb_read(12, rd); check_eq("DBG2_RST", rd, 32'h00C0_0000);

    // 2. Trafico aleatorio restringido (DLAB = 0) con autochequeo
    repeat (40) begin
      void'(std::randomize(reg_pick, do_wr, wdata) with {
        reg_pick inside {1, 3, 7};
      });

      if (do_wr) begin
        case (reg_pick)
          1: begin
            wb_write(1, wdata);
            exp_ier = wdata & 8'h0F;
          end
          3: begin
            wdata[7] = 1'b0;
            wb_write(3, wdata);
            exp_lcr = wdata;
          end
          7: begin
            wb_write(7, wdata);
            exp_scr = wdata;
          end
        endcase
      end
      else begin
        wb_read(reg_pick, rd);
        case (reg_pick)
          1: check_eq("RAND_IER", rd, {24'h0, exp_ier});
          3: check_eq("RAND_LCR", rd, {24'h0, exp_lcr});
          7: check_eq("RAND_SCR", rd, {24'h0, exp_scr});
        endcase
      end
    end

    // 3. Divisor aleatorio con DLAB = 1 (DLM y DLL)
    repeat (5) begin
      bit [7:0] dlm_v, dll_v;
      void'(std::randomize(dlm_v, dll_v));
      wb_write(3, exp_lcr | 8'h80);
      wb_write(1, dlm_v);
      wb_write(0, dll_v);
      wb_read(1, rd); check_eq("RAND_DLM", rd, {24'h0, dlm_v});
      wb_read(0, rd); check_eq("RAND_DLL", rd, {24'h0, dll_v});
      wb_write(3, exp_lcr);
    end

    // 4. Asegurar al menos un flanco de subida y bajada en int_o (THRE)
    wb_write(1, 8'h00);
    wb_idle(2);
    wb_write(1, 8'h02);
    wb_idle(4);
    wb_read(2, rd);
    wb_write(1, 8'h00);
    wb_idle(4);

    // 5. Rafaga aleatoria con wb_sel_i ilegal (AMB-05)
    p_sequencer.cfg.bad_sel_pct = 50;
    repeat (10) begin
      void'(std::randomize(do_wr, wdata));
      if (do_wr) wb_write(7, wdata, 1'b1);
      else       wb_read(7, rd, 1'b1);
    end
    p_sequencer.cfg.bad_sel_pct = 0;

    // 6. Reset asincrono con ancho y fase aleatorios + recuperacion
    rst_w  = $urandom_range(5, 1);
    rst_ph = $urandom_range(19, 1);
    p_sequencer.async_reset(rst_w, rst_ph);
    wb_idle(2);
    wb_read(3, rd); check_eq("LCR_POST_RST", rd, 32'h0000_0003);
    wb_read(7, rd); check_eq("SCR_POST_RST", rd, 32'h0000_0000);

  // --- Caso 1: wb_sel_i invalido (sel_injected) sin colgarse ---
    p_sequencer.cfg.bad_sel_pct = 100;
    repeat (4) begin
      void'(std::randomize(wdata));
      wb_write(7, wdata, 1'b1);
      wb_read(7, rd, 1'b1);
    end
    p_sequencer.cfg.bad_sel_pct = 0;
    wb_idle(2);

    // --- Caso 2: Reset asincrono en medio de un acceso (aborted) ---
    fork
      begin
        wb_write(7, 8'h3C);
      end
      begin
        #5; // cae en medio del ciclo activo
        p_sequencer.async_reset(3, 5.0);
      end
    join
    wb_idle(2);
    wb_read(3, rd);
    check_eq("LCR_AFTER_ABORT_RST", rd, 32'h0000_0003);

    // --- Caso 3: Condicion de timeout ---
    // Ajusta la direccion o el knob de timeout segun como lo hayas implementado en wb_driver/wb_if
    fork
      begin
        wb_read(32'h1F, rd);
      end
      begin
        #2000ns;
        `uvm_error("SMOKE_TMO", "El acceso de timeout no libero o no completo a tiempo")
      end
    join_any
    disable fork;
    wb_idle(2);

  endtask
endclass : wb_smoke_seq


class wb_smoke_test extends uvm_test;
  `uvm_component_utils(wb_smoke_test)

  wb_agent_cfg  cfg;
  uart_wb_agent wb_agt;
  wb_smoke_sub  sub;

  function new(string name = "wb_smoke_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg = wb_agent_cfg::type_id::create("cfg");
    if (!uvm_config_db#(virtual wb_if)::get(this, "", UART_KEY_WB_VIF, cfg.vif))
      `uvm_fatal("NOVIF", "wb_smoke_test: no se encontro wb_vif")

    uvm_config_db#(wb_agent_cfg)::set(this, "wb_agt*", UART_KEY_CFG, cfg);
    wb_agt = uart_wb_agent::type_id::create("wb_agt", this);
    sub    = wb_smoke_sub::type_id::create("sub", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    wb_agt.ap.connect(sub.wb_imp);
    wb_agt.rst_ap.connect(sub.rst_imp);
    wb_agt.int_ap.connect(sub.int_imp);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

  task run_phase(uvm_phase phase);
    wb_smoke_seq seq;
    phase.raise_objection(this);
    seq = wb_smoke_seq::type_id::create("seq");
    seq.start(wb_agt.sqr);
    phase.drop_objection(this);
  endtask
endclass : wb_smoke_test