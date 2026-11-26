`timescale 1ns/1ps

module tb_wb_smoke;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import wb_smoke_pkg::*;

  logic clk = 1'b0;
  always #10 clk = ~clk;

  wb_if wb_vif(clk);

  wire stx_o, rts_o, dtr_o;

  uart_top dut (
    .wb_clk_i  (clk),
    .wb_rst_i  (wb_vif.rst),
    .wb_adr_i  (wb_vif.adr),
    .wb_dat_i  (wb_vif.dat_m2s),
    .wb_dat_o  (wb_vif.dat_s2m),
    .wb_we_i   (wb_vif.we),
    .wb_stb_i  (wb_vif.stb),
    .wb_cyc_i  (wb_vif.cyc),
    .wb_ack_o  (wb_vif.ack),
    .wb_sel_i  (wb_vif.sel),
    .int_o     (wb_vif.irq),
    .stx_pad_o (stx_o),
    .srx_pad_i (1'b1),
    .rts_pad_o (rts_o),
    .cts_pad_i (1'b1),
    .dtr_pad_o (dtr_o),
    .dsr_pad_i (1'b1),
    .ri_pad_i  (1'b1),
    .dcd_pad_i (1'b1)
  );

  initial begin
    wb_vif.rst = 1'b1;
    repeat (4) @(posedge clk);
    #3;
    wb_vif.rst = 1'b0;
  end

  initial begin
    uvm_config_db#(virtual wb_if)::set(null, UART_PATH_VIF, UART_KEY_WB_VIF, wb_vif);
    run_test("wb_smoke_test");
  end
endmodule : tb_wb_smoke