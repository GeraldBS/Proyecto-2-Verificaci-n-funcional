// -----------------------------------------------------------------------------
// uart_hello_pkg.sv
// Prueba de humo para validar que el DUT quedó bien instanciado y que las
// interfaces virtuales llegan al ambiente por uvm_config_db.
//
// IMPORTANTE: esta prueba accede a la interfaz directamente desde el test
// solo para comprobar la instancia. En el proyecto, el acceso al bus lo
// hace el driver del agente Wishbone (o el RAL a través del adaptador).
// No la usen como base del ambiente.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

package uart_hello_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class uart_hello_test extends uvm_test;
    `uvm_component_utils(uart_hello_test)

    virtual wb_if       wb_vif;
    virtual uart_ser_if ser_vif;
    virtual modem_if    mdm_vif;

    function new(string name = "uart_hello_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual wb_if)::get(this, "", "wb_vif", wb_vif))
        `uvm_fatal("NOVIF", "No se encontró wb_vif en uvm_config_db")
      if (!uvm_config_db#(virtual uart_ser_if)::get(this, "", "ser_vif", ser_vif))
        `uvm_fatal("NOVIF", "No se encontró ser_vif en uvm_config_db")
      if (!uvm_config_db#(virtual modem_if)::get(this, "", "mdm_vif", mdm_vif))
        `uvm_fatal("NOVIF", "No se encontró mdm_vif en uvm_config_db")
    endfunction

    // Lectura Wishbone de un registro de 8 bits.
    //   reg_idx: índice del registro de la especificación (0 = RBR ... 6 = MSR).
    // En modo de 32 bits sin LITLE_ENDIAN, el byte se selecciona con
    // wb_sel_i = 4'b1000 >> reg_idx[1:0] y viaja en el carril 3 - reg_idx[1:0].
    task automatic wb_read(input bit [4:0] reg_idx, output bit [7:0] data);
      int lane;
      @(wb_vif.drv_cb);
      wb_vif.drv_cb.adr <= reg_idx;
`ifdef DATA_BUS_WIDTH_8
      wb_vif.drv_cb.sel <= 4'b0001;            // ignorado en modo de 8 bits
      lane = 0;
`else
      wb_vif.drv_cb.sel <= 4'b1000 >> reg_idx[1:0];
      lane = 3 - reg_idx[1:0];
`endif
      wb_vif.drv_cb.we  <= 1'b0;
      wb_vif.drv_cb.cyc <= 1'b1;
      wb_vif.drv_cb.stb <= 1'b1;
      do @(wb_vif.drv_cb); while (wb_vif.drv_cb.ack !== 1'b1);
      data = wb_vif.drv_cb.dat_s2m[8*lane +: 8];
      wb_vif.drv_cb.cyc <= 1'b0;
      wb_vif.drv_cb.stb <= 1'b0;
    endtask

    task run_phase(uvm_phase phase);
      bit [7:0] lcr, iir, lsr;
      phase.raise_objection(this);

      // Esperar a que termine el reset que genera tb_top.
      wait (wb_vif.rst === 1'b0);
      repeat (2) @(wb_vif.drv_cb);

      wb_read(5'd3, lcr);
      wb_read(5'd2, iir);
      wb_read(5'd5, lsr);

      `uvm_info("HELLO", $sformatf("LCR = 0x%02h, IIR = 0x%02h, LSR = 0x%02h", lcr, iir, lsr), UVM_LOW)

      // Según la especificación, LCR se reinicia en 8'b0000_0011.
      if (lcr !== 8'h03)
        `uvm_error("HELLO", $sformatf("LCR después de reset = 0x%02h, se esperaba 0x03", lcr))
      else
        `uvm_info("HELLO", "Instancia correcta: el DUT responde por Wishbone", UVM_LOW)

      if (ser_vif.stx !== 1'b1)
        `uvm_error("HELLO", "stx_pad_o debería estar en reposo (1) después de reset")

      repeat (10) @(wb_vif.drv_cb);
      phase.drop_objection(this);
    endtask

  endclass : uart_hello_test

endpackage : uart_hello_pkg
