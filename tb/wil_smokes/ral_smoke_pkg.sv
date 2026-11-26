package ral_smoke_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Ajusta estos includes si tus archivos del agente Wishbone tienen otro orden/nombre
  `include "wishbone_agent/wb_agent_cfg.sv"
  `include "wishbone_agent/wb_item.sv"
  `include "wishbone_agent/wb_events.sv"
  `include "wishbone_agent/wb_sequencer.sv"
  `include "wishbone_agent/wb_driver.sv"
  `include "wishbone_agent/wb_monitor.sv"
  `include "wishbone_agent/uart_int_monitor.sv"
  `include "wishbone_agent/wb_agent.sv"

  `include "register_model/uart_ral.sv"
  `include "wil_smokes/ral_smoke_test.sv"
endpackage : ral_smoke_pkg