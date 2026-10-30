// -----------------------------------------------------------------------------
// tb_top.sv
// Módulo superior del banco de pruebas: genera reloj y reset, instancia las
// interfaces y el DUT, enlaza las aserciones y entrega las interfaces
// virtuales al ambiente UVM antes de run_test().
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`include "uart_defines.v"

module tb_top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import uart_hello_pkg::*;   // agreguen aquí el paquete de su ambiente

  // ---------------------------------------------------------------------------
  // Reloj y reset
  // ---------------------------------------------------------------------------
  // 50 MHz: con DL = 1 la tasa es 50e6 / 16 = 3.125 Mbaud (simulaciones rápidas).
  parameter real CLK_PERIOD_NS = 20.0;

  logic clk = 1'b0;
  always #(CLK_PERIOD_NS / 2.0) clk = ~clk;

  // ---------------------------------------------------------------------------
  // Interfaces
  // ---------------------------------------------------------------------------
  wb_if       wb  (clk);
  uart_ser_if ser (clk);
  modem_if    mdm (clk);

  // Reset inicial y valores de reposo mientras los drivers no toman control.
  // Si su plan incluye reset aleatorio, muevan el manejo de wb.rst a un
  // componente del ambiente y eliminen esta parte.
  initial begin
    wb.rst     = 1'b1;
    wb.cyc     = 1'b0;
    wb.stb     = 1'b0;
    wb.we      = 1'b0;
    wb.sel     = '0;
    wb.adr     = '0;
    wb.dat_m2s = '0;
    ser.srx    = 1'b1;   // línea serie en reposo: si queda en X o 0, el receptor ve bits de inicio
    mdm.cts    = 1'b1;
    mdm.dsr    = 1'b1;
    mdm.ri     = 1'b1;
    mdm.dcd    = 1'b1;
    repeat (5) @(posedge clk);
    wb.rst     = 1'b0;
  end

  // ---------------------------------------------------------------------------
  // DUT: conexiones siempre por nombre
  // ---------------------------------------------------------------------------
  uart_top dut (
    .wb_clk_i  (clk),
    .wb_rst_i  (wb.rst),
    .wb_adr_i  (wb.adr),
    .wb_dat_i  (wb.dat_m2s),
    .wb_dat_o  (wb.dat_s2m),
    .wb_we_i   (wb.we),
    .wb_stb_i  (wb.stb),
    .wb_cyc_i  (wb.cyc),
    .wb_ack_o  (wb.ack),
    .wb_sel_i  (wb.sel),
    .int_o     (wb.irq),
    .stx_pad_o (ser.stx),
    .srx_pad_i (ser.srx),
    .rts_pad_o (mdm.rts),
    .cts_pad_i (mdm.cts),
    .dtr_pad_o (mdm.dtr),
    .dsr_pad_i (mdm.dsr),
    .ri_pad_i  (mdm.ri),
    .dcd_pad_i (mdm.dcd)
`ifdef UART_HAS_BAUDRATE_OUTPUT
   ,.baud_o    (ser.baud)
`endif
  );

`ifndef UART_HAS_BAUDRATE_OUTPUT
  assign ser.baud = 1'b0;
`endif

  // ---------------------------------------------------------------------------
  // Aserciones: bind a todas las instancias del módulo uart_top
  // ---------------------------------------------------------------------------
  bind uart_top uart_wb_sva u_wb_sva (
    .wb_clk_i (wb_clk_i),
    .wb_rst_i (wb_rst_i),
    .wb_adr_i (wb_adr_i),
    .wb_dat_i (wb_dat_i),
    .wb_sel_i (wb_sel_i),
    .wb_we_i  (wb_we_i),
    .wb_stb_i (wb_stb_i),
    .wb_cyc_i (wb_cyc_i),
    .wb_ack_o (wb_ack_o)
  );

  // ---------------------------------------------------------------------------
  // Entregar las interfaces al ambiente y arrancar la prueba
  // ---------------------------------------------------------------------------
  initial begin
    uvm_config_db#(virtual wb_if)::set      (null, "uvm_test_top*", "wb_vif",  wb);
    uvm_config_db#(virtual uart_ser_if)::set(null, "uvm_test_top*", "ser_vif", ser);
    uvm_config_db#(virtual modem_if)::set   (null, "uvm_test_top*", "mdm_vif", mdm);
    run_test();   // el nombre de la prueba viene de +UVM_TESTNAME
  end

  // ---------------------------------------------------------------------------
  // Formas de onda (opcional): +define+DUMP_FSDB para Verdi
  // ---------------------------------------------------------------------------
`ifdef DUMP_FSDB
  initial begin
    $fsdbDumpfile("waves.fsdb");
    $fsdbDumpvars(0, tb_top);
  end
`endif

endmodule : tb_top
