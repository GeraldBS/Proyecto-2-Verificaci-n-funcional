//////////////////////////////////////////////////////////////////////////////////
// uart_pkg.sv
// Paquete del ambiente UVM del UART 16550.
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps          // unidad de tiempo 1 ns, precisión 1 ps
`include "uart_defines.v"   // anchos del bus (UART_ADDR_WIDTH y UART_DATA_WIDTH)

package uart_pkg;

  import uvm_pkg::*;          // clases y funciones de UVM
  `include "uvm_macros.svh"   // macros de UVM

  // uvm_config_db: rutas y nombres con que se publican interfaces y objetos

  localparam string UART_PATH_VIF    = "uvm_test_top*";   // ruta donde tb_top publica las interfaces
  localparam string UART_KEY_WB_VIF  = "wb_vif";          // nombre de la interfaz Wishbone
  localparam string UART_KEY_SER_VIF = "ser_vif";         // nombre de la interfaz serie
  localparam string UART_KEY_MDM_VIF = "mdm_vif";         // nombre de la interfaz de módem

  localparam string UART_PATH_ENV     = "env*";           // uart_env_cfg
  localparam string UART_PATH_WB_AGT  = "env.wb_agt*";    // wb_agent_cfg
  localparam string UART_PATH_SER_AGT = "env.ser_agt*";   // uart_ser_agent_cfg
  localparam string UART_PATH_MDM_AGT = "env.mdm_agt*";   // modem_agent_cfg
  localparam string UART_PATH_SCB     = "env.scb*";       // uart_scb_cfg
  localparam string UART_PATH_COV     = "env.cov*";       // uart_cov_cfg

  // nombre del campo con el que se publican todos los objetos de configuración
  localparam string UART_KEY_CFG = "cfg";

  // Tipos y objetos de configuración 
  `include "config/uart_types.sv"
  `include "config/uart_line_cfg.sv"
  `include "config/uart_ctrl_cfg.sv"
  `include "config/uart_agent_cfgs.sv"
  `include "config/uart_env_cfg.sv"

  // Agente Wishbone y monitor de int_o 
  `include "wishbone_agent/wb_item.sv"
  `include "wishbone_agent/wb_events.sv"
  `include "wishbone_agent/wb_driver.sv"
  `include "wishbone_agent/wb_sequencer.sv"
  `include "wishbone_agent/wb_monitor.sv"
  `include "wishbone_agent/uart_int_monitor.sv"
  `include "wishbone_agent/wb_agent.sv"
  `include "wishbone_agent/wb_seqs.sv"

  // Agente serie y agente de módem 
  `include "serial_agent/ser_item.sv"
  `include "serial_agent/ser_sequencer.sv"
  `include "serial_agent/ser_driver.sv"
  `include "serial_agent/ser_tx_monitor.sv"
  `include "serial_agent/ser_rx_monitor.sv"
  `include "serial_agent/uart_ser_agent.sv"

  `include "modem_agent/mdm_item.sv"
  `include "modem_agent/modem_sequencer.sv"
  `include "modem_agent/modem_driver.sv"
  `include "modem_agent/modem_monitor.sv"
  `include "modem_agent/modem_agent.sv"

  // Modelo de registros 
  `include "register_model/uart_ral.sv"

  // Scoreboard y modelo de referencia 
  `include "scoreboard/uart_model_evt.sv"
  `include "scoreboard/uart_scoreboard.sv"

  // Cobertura y secuencias 
  `include "coverage/uart_cov.sv"
  `include "sequences/uart_virtual_sequencer.sv"
  `include "sequences/uart_seqs.sv"

  // Ambiente 
  `include "environment/uart_env.sv"
  `include "uart_base_test.sv"
  `include "humo/uart_smoke_test.sv"
  `include "humo/uart_scb_smoke_test.sv"
  `include "uart_frame_sweep_test.sv"
  `include "uart_multi_ep_test.sv"

endpackage : uart_pkg
