//////////////////////////////////////////////////////////////////////////////
// uart_base_test:
// Prueba base del proyecto: arma uart_env_cfg, lee los plusargs, toma las interfaces de tb_top,
// publica la configuración (tabla 9.3 del plan) y corre uart_main_vseq. Las pruebas
// uart_frame_sweep_test y uart_multi_ep_test la extienden y solo redefinen test_cfg().
//////////////////////////////////////////////////////////////////////////////

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
    test_cfg();   // después de los plusargs: lo que fije una prueba hija manda sobre ellos

    // las interfaces las publica tb_top antes de run_test()
    if (!uvm_config_db#(virtual wb_if)::get(this, "", "wb_vif", cfg.wb.vif))
      `uvm_fatal("NOVIF", "wb_vif no se encontró en uvm_config_db")
    if (!uvm_config_db#(virtual uart_ser_if)::get(this, "", "ser_vif", cfg.ser.vif))
      `uvm_fatal("NOVIF", "ser_vif no se encontró en uvm_config_db")
    if (!uvm_config_db#(virtual modem_if)::get(this, "", "mdm_vif", cfg.mdm.vif))
      `uvm_fatal("NOVIF", "mdm_vif no se encontró en uvm_config_db")
    cfg.cov.wb_vif = cfg.wb.vif;

    // rutas de la tabla 9.3 del plan
    uvm_config_db#(uart_env_cfg)::set       (this, "env*",         "env_cfg", cfg);
    uvm_config_db#(wb_agent_cfg)::set       (this, "env.wb_agt*",  "cfg",     cfg.wb);
    uvm_config_db#(uart_ser_agent_cfg)::set (this, "env.ser_agt*", "cfg",     cfg.ser);
    uvm_config_db#(modem_agent_cfg)::set    (this, "env.mdm_agt*", "cfg",     cfg.mdm);
    uvm_config_db#(uart_scb_cfg)::set       (this, "env.scb*",     "cfg",     cfg.scb);
    uvm_config_db#(uart_cov_cfg)::set       (this, "env.cov*",     "cfg",     cfg.cov);

    env = uart_env::type_id::create("env", this);
  endfunction

  // las pruebas hijas lo sobreescriben para fijar episodios y cosas así; en la base no cambia nada
  virtual function void test_cfg();
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
    // 2 Tc del último formato, para que termine el carácter que quede en la línea
    phase.phase_done.set_drain_time(this, 2.0 * cfg.line.tc_cycles() * UART_CLK_NS * 1ns);
    phase.drop_objection(this, "terminó uart_main_vseq");
  endtask

  function void report_phase(uvm_phase phase);
    uvm_report_server rs = uvm_report_server::get_server();
    int unsigned errs = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
    int unsigned bugs = rs.get_id_count("AMB-03") + rs.get_id_count("AMB-04");
    super.report_phase(phase);
    // con +UART_SCB_DUT_BUG_SEV=error las diferencias conocidas ya sumaron como UVM_ERROR; no cuentan
    if (cfg.scb.dut_bug_sev == UVM_ERROR) errs = (errs > bugs) ? errs - bugs : 0;
    if (errs == 0)
      `uvm_info("RESULT", $sformatf("PASA (diferencias conocidas del DUT: %0d)", bugs), UVM_NONE)
    else
      `uvm_info("RESULT", $sformatf("FALLA: %0d errores (diferencias conocidas del DUT: %0d)", errs, bugs), UVM_NONE)
  endfunction
endclass : uart_base_test