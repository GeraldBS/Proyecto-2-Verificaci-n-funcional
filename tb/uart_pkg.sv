//////////////////////////////////////////////////////////////////////////////////
// uart_pkg.sv
// Paquete del ambiente UVM del UART 16550.
//
// El orden de los include sigue las dependencias: primero tipos y
// configuración, luego transacciones y agentes, RAL y scoreboard, y al final
// cobertura, secuencias, ambiente y prueba. Los nombres de los archivos de
// cada parte están en docs/contrato_ambiente.md.
//
// Los .svh/.sv que se incluyen aquí NO van en filelist.f: se compilan solo a
// través de estos `include (cada archivo define clases de este paquete).
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

  // Tipos y objetos de configuración (Gerald)
  `include "config/uart_types.svh"
  `include "config/uart_line_cfg.svh"
  `include "config/uart_ctrl_cfg.svh"
  `include "config/uart_agent_cfgs.svh"
  `include "config/uart_env_cfg.svh"

  // Agente Wishbone y monitor de int_o (Leonardo)
  `include "wishbone_agent/wb_item.sv"
  `include "wishbone_agent/wb_events.sv"
  `include "wishbone_agent/wb_driver.sv"
  `include "wishbone_agent/wb_sequencer.sv"
  `include "wishbone_agent/wb_monitor.sv"
  `include "wishbone_agent/uart_int_monitor.sv"
  `include "wishbone_agent/wb_agent.sv"
  `include "wishbone_agent/wb_seqs.sv"

  // Agente serie y agente de módem (Wilbert)
  `include "serial_agent/ser_item.svh"
  `include "serial_agent/uart_ser_agent.svh"
  `include "modem_agent/mdm_item.svh"
  `include "modem_agent/modem_agent.svh"

  // Modelo de registros (Leonardo)
  `include "register_model/uart_ral.svh"

  // Scoreboard y modelo de referencia (Wilbert)
  `include "scoreboard/uart_model_evt.svh"
  `include "scoreboard/uart_scoreboard.svh"

  // Cobertura y secuencias (Gerald)
  `include "coverage/uart_cov.svh"
  `include "sequences/uart_virtual_sequencer.svh"
  `include "sequences/uart_seqs.svh"

  // Ambiente (Leonardo) y prueba
  `include "environment/uart_env.svh"
  `include "uart_base_test.svh"

endpackage : uart_pkg
