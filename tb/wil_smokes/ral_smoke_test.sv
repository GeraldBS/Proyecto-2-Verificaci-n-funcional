class ral_smoke_seq extends uvm_sequence #(uvm_sequence_item);
  `uvm_object_utils(ral_smoke_seq)

  uart_reg_block regm;

  function new(string name = "ral_smoke_seq");
    super.new(name);
  endfunction

  task check_front_vs_back(uvm_reg r, string tag, bit use_dlab1 = 1'b0);
    uvm_status_e   st_f, st_b;
    uvm_reg_data_t val_f, val_b;
    uvm_reg_map    m = use_dlab1 ? regm.dlab1_map : regm.dlab0_map;

    r.read(st_f, val_f, UVM_FRONTDOOR, m, this);
    r.read(st_b, val_b, UVM_BACKDOOR,  null, this);

    if (st_f != UVM_IS_OK || st_b != UVM_IS_OK)
      `uvm_error("RAL_SMOKE", $sformatf("%s: error de estado front=%0d back=%0d", tag, st_f, st_b))
    else if (val_f !== val_b)
      `uvm_error("RAL_SMOKE", $sformatf("%s: desajuste frontdoor=0x%0h vs backdoor=0x%0h", tag, val_f, val_b))
    else
      `uvm_info("RAL_SMOKE", $sformatf("%s: OK frontdoor == backdoor == 0x%0h", tag, val_f), UVM_LOW)
  endtask

  virtual task body();
    uvm_status_e         status;
    uvm_reg_data_t       mir_val, bd_val;
    uvm_reg_hw_reset_seq hw_rst_seq;

    if (regm == null)
      `uvm_fatal("RAL_SMOKE", "regm es null en ral_smoke_seq")

    // 1) Secuencia integrada de valores de reset (respeta set_test_exclusions)
    hw_rst_seq = uvm_reg_hw_reset_seq::type_id::create("hw_rst_seq");
    hw_rst_seq.model = regm;
    hw_rst_seq.start(null);

    // 2) Comparacion directa frontdoor vs backdoor tras reset
    check_front_vs_back(regm.ier, "IER_RST");
    check_front_vs_back(regm.lcr, "LCR_RST");
    check_front_vs_back(regm.scr, "SCR_RST");

    // 3) Escritura por RAL y verificacion de actualizacion del mirror (predictor explicito)
    regm.scr.write(status, 8'h5A, UVM_FRONTDOOR, regm.dlab0_map, this);
    if (status != UVM_IS_OK)
      `uvm_error("RAL_SMOKE", $sformatf("Fallo escritura RAL en SCR: status=%0d", status))

    mir_val = regm.scr.get_mirrored_value();
    if (mir_val !== 8'h5A)
      `uvm_error("RAL_SMOKE", $sformatf("Mirror SCR esperado 0x5A, obtenido 0x%0h", mir_val))
    else
      `uvm_info("RAL_SMOKE", $sformatf("Mirror SCR OK: 0x%0h", mir_val), UVM_LOW)

    // 4) Verificacion de MCR (WO): escribir por frontdoor y comprobar por backdoor
    regm.mcr.write(status, 8'h15, UVM_FRONTDOOR, regm.dlab0_map, this);
    regm.mcr.read(status, bd_val, UVM_BACKDOOR, null, this);
    if (bd_val !== 8'h15)
      `uvm_error("RAL_SMOKE", $sformatf("MCR backdoor esperado 0x15, obtenido 0x%0h", bd_val))
    else
      `uvm_info("RAL_SMOKE", $sformatf("MCR backdoor OK: 0x%0h", bd_val), UVM_LOW)

    // 5) Conmutacion de mapas DLAB = 1 y DLAB = 0
    regm.lcr.write(status, 8'h83, UVM_FRONTDOOR, regm.dlab0_map, this); // DLAB = 1
    regm.dll.write(status, 8'h12, UVM_FRONTDOOR, regm.dlab1_map, this);
    regm.dlm.write(status, 8'h34, UVM_FRONTDOOR, regm.dlab1_map, this);
    check_front_vs_back(regm.dll, "DLL_DLAB1", 1'b1);
    check_front_vs_back(regm.dlm, "DLM_DLAB1", 1'b1);

    // Regresar a DLAB = 0 y comprobar que dlab0_map responde bien
    regm.lcr.write(status, 8'h03, UVM_FRONTDOOR, regm.dlab0_map, this); // DLAB = 0
    regm.ier.write(status, 8'h05, UVM_FRONTDOOR, regm.dlab0_map, this);
    check_front_vs_back(regm.ier, "IER_DLAB0", 1'b0);

    regm.scr.write(status, 8'hA5, UVM_FRONTDOOR, regm.dlab0_map, this);
    mir_val = regm.scr.get_mirrored_value();
    if (mir_val !== 8'hA5)
      `uvm_error("RAL_SMOKE", $sformatf("Mirror SCR tras DLAB=0 esperado 0xA5, obtenido 0x%0h", mir_val))
    else
      `uvm_info("RAL_SMOKE", $sformatf("Mirror SCR tras DLAB=0 OK: 0x%0h", mir_val), UVM_LOW)
  endtask
endclass : ral_smoke_seq


class ral_smoke_test extends uvm_test;
  `uvm_component_utils(ral_smoke_test)

  wb_agent_cfg       wb_cfg;
  uart_wb_agent      wb_agt;
  uart_reg_block     regm;
  uart_reg_adapter   adapter;
  uart_reg_predictor predictor;

  function new(string name = "ral_smoke_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    wb_cfg = wb_agent_cfg::type_id::create("wb_cfg");
    if (!uvm_config_db#(virtual wb_if)::get(this, "", "wb_vif", wb_cfg.vif))
      `uvm_fatal("RAL_TEST", "No se encontro wb_vif en uvm_config_db")

    uvm_config_db#(wb_agent_cfg)::set(this, "wb_agt*", "cfg", wb_cfg);

    wb_agt    = uart_wb_agent::type_id::create("wb_agt", this);
    regm      = uart_reg_block::type_id::create("regm");
    adapter   = uart_reg_adapter::type_id::create("adapter");
    predictor = uart_reg_predictor::type_id::create("predictor", this);

    regm.build();
    regm.set_test_exclusions();
    regm.reset();
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Conectar ambos mapas al mismo sequencer y adaptador, con prediccion explicita
    regm.dlab0_map.set_sequencer(wb_agt.sqr, adapter);
    regm.dlab1_map.set_sequencer(wb_agt.sqr, adapter);
    regm.dlab0_map.set_auto_predict(0);
    regm.dlab1_map.set_auto_predict(0);

    // Conectar el predictor al monitor del agente Wishbone
    predictor.regm    = regm;
    predictor.map     = regm.dlab0_map;
    predictor.adapter = adapter;
    wb_agt.ap.connect(predictor.bus_in);
  endfunction

  virtual task run_phase(uvm_phase phase);
    ral_smoke_seq seq;
    phase.raise_objection(this);

    // Reset inicial limpio antes de arrancar el RAL
    wb_agt.sqr.async_reset(5, 2.0);
    repeat (3) @(posedge wb_cfg.vif.clk);

    seq = ral_smoke_seq::type_id::create("seq");
    seq.regm = regm;
    seq.start(null);

    repeat (5) @(posedge wb_cfg.vif.clk);
    phase.drop_objection(this);
  endtask
endclass : ral_smoke_test