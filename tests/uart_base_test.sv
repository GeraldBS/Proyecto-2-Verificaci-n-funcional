//////////////////////////////////////////////////////////////////////
// uart_base_test: la única prueba del proyecto                   
// Arma la configuración, lee los plusargs, la publica y corre la
// secuencia principal. Los casos de esquina son esta misma prueba con
// otro archivo .args (sección 6 del plan).
//////////////////////////////////////////////////////////////////////
class uart_base_test extends uvm_test;
  `uvm_component_utils(uart_base_test)

  uart_env_cfg cfg;
  uart_env     env;

  function new(string name = "uart_base_test", uvm_component parent = null); // constructor
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg = uart_env_cfg::type_id::create("cfg");
    cfg.parse_plusargs();

    // las interfaces las publica tb_top antes de run_test()
    if (!uvm_config_db#(virtual wb_if)::get(this, "", "wb_vif", cfg.wb.vif))
      `uvm_fatal("NOVIF", "wb_vif no se encontró  uvm_config_db")
    if (!uvm_config_db#(virtual uart_ser_if)::get(this, "", "ser_vif", cfg.ser.vif))
      `uvm_fatal("NOVIF", "ser_vif no se encontró en uvm_config_db")
    if (!uvm_config_db#(virtual modem_if)::get(this, "", "mdm_vif", cfg.mdm.vif))
      `uvm_fatal("NOVIF", "mdm_vif no se encontró en uvm_config_db")
    cfg.cov.wb_vif = cfg.wb.vif;

    // rutas de la tabla 9.3 del plan
    uvm_config_db#(uart_env_cfg)::set (this, "env*",         "env_cfg", cfg);
    uvm_config_db#(wb_agent_cfg)::set (this, "env.wb_agt*",  "cfg",     cfg.wb);
    uvm_config_db#(uart_ser_agent_cfg)::set (this, "env.ser_agt*", "cfg",     cfg.ser);
    uvm_config_db#(modem_agent_cfg)::set (this, "env.mdm_agt*", "cfg",     cfg.mdm);
    uvm_config_db#(uart_scb_cfg)::set (this, "env.scb*",     "cfg",     cfg.scb);
    uvm_config_db#(uart_cov_cfg)::set (this, "env.cov*",     "cfg",     cfg.cov);

    env = uart_env::type_id::create("env", this);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase); // siguiente fase de elaboration
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
    cfg.print_knobs();
  endfunction

  task run_phase(uvm_phase phase);
    uart_main_vseq vseq = uart_main_vseq::type_id::create("vseq");
    phase.raise_objection(this, "corre uart_main_vseq");
    vseq.start(env.vsqr);
    phase.phase_done.set_drain_time(this, 2.0 * cfg.line.tc_cycles() * UART_CLK_NS * 1ns);
    phase.drop_objection(this, "terminó uart_main_vseq");
  endtask

  function void report_phase(uvm_phase phase);
    uvm_report_server rs = uvm_report_server::get_server();
    int unsigned errs  = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
    int unsigned bugs  = rs.get_id_count("DUT_BUG");
    super.report_phase(phase);
    if (errs == 0)
      `uvm_info("RESULT", $sformatf("PASA (diferencias conocidas del DUT reportadas: %0d)", bugs), UVM_NONE)
    else
      `uvm_info("RESULT", $sformatf("FALLA: %0d errores (diferencias conocidas del DUT: %0d)", errs, bugs), UVM_NONE)
  endfunction
endclass : uart_base_test
