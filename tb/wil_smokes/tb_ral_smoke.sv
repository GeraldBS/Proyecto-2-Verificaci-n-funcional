`timescale 1ns/1ps

module tb_top;
  import uvm_pkg::*;
  import ral_smoke_pkg::*;

  logic clk;
  initial clk = 1'b0;
  always #10 clk = ~clk; // 50 MHz

  wb_if wb_vif(.clk(clk));

  // Senales serie y modem en reposo para la prueba de humo del RAL
  logic srx_pad_i = 1'b1;
  logic stx_pad_o;
  logic rts_pad_o, dtr_pad_o;
  logic cts_pad_i = 1'b0;
  logic dsr_pad_i = 1'b0;
  logic ri_pad_i  = 1'b0;
  logic dcd_pad_i = 1'b0;

  uart_top dut (
    .wb_clk_i  (clk),
    .wb_rst_i  (wb_vif.rst),
    .wb_adr_i  (wb_vif.adr),
    .wb_dat_i  (wb_vif.dat_i),
    .wb_dat_o  (wb_vif.dat_o),
    .wb_we_i   (wb_vif.we),
    .wb_stb_i  (wb_vif.stb),
    .wb_cyc_i  (wb_vif.cyc),
    .wb_ack_o  (wb_vif.ack),
    .wb_sel_i  (wb_vif.sel),
    .int_o     (wb_vif.irq),
    .stx_pad_o (stx_pad_o),
    .srx_pad_i (srx_pad_i),
    .rts_pad_o (rts_pad_o),
    .cts_pad_i (cts_pad_i),
    .dtr_pad_o (dtr_pad_o),
    .dsr_pad_i (dsr_pad_i),
    .ri_pad_i  (ri_pad_i),
    .dcd_pad_i (dcd_pad_i)
  );

  initial begin
    uvm_config_db#(virtual wb_if)::set(null, "uvm_test_top*", "wb_vif", wb_vif);
    run_test("ral_smoke_test");
  end
endmodule : tb_top