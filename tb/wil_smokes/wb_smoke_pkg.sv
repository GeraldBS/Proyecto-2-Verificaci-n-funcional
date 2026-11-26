`timescale 1ns/1ps
`include "uart_defines.v"

package wb_smoke_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam string UART_PATH_VIF   = "uvm_test_top*";
  localparam string UART_KEY_WB_VIF = "wb_vif";
  localparam string UART_KEY_CFG    = "cfg";

  `include "config/uart_types.sv"

  class wb_agent_cfg extends uvm_object;
    `uvm_object_utils(wb_agent_cfg)
    virtual wb_if           vif;
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    int unsigned gap_max       = 4;
    int unsigned gap_zero_pct  = 60;
    int unsigned stb_delay_pct = 20;
    int unsigned stb_delay_max = 3;
    int unsigned bad_sel_pct   = 0;

    function new(string name = "wb_agent_cfg");
      super.new(name);
    endfunction
  endclass : wb_agent_cfg

  `include "wishbone_agent/wb_item.sv"
  `include "wishbone_agent/wb_events.sv"
  `include "wishbone_agent/wb_driver.sv"
  `include "wishbone_agent/wb_sequencer.sv"
  `include "wishbone_agent/wb_monitor.sv"
  `include "wishbone_agent/uart_int_monitor.sv"
  `include "wishbone_agent/wb_agent.sv"
  `include "wishbone_agent/wb_seqs.sv"

  `include "wil_smokes/wb_smoke_test.sv"
endpackage : wb_smoke_pkg