//////////////////////////////////////////////////////////////////////
// uart_wb_sva: aserciones de la interfaz Wishbone   
//
// Cada propiedad tiene su cover. Los fallos se reportan con rep_err para
// que el contador de UVM_ERROR de la prueba los vea.
//////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "uart_defines.v"

module uart_wb_sva (
  input logic                            wb_clk_i,
  input logic                            wb_rst_i,
  input logic [`UART_ADDR_WIDTH-1:0]     wb_adr_i,
  input logic [`UART_DATA_WIDTH-1:0]     wb_dat_i,
  input logic [`UART_DATA_WIDTH-1:0]     wb_dat_o,
  input logic [3:0]                      wb_sel_i,
  input logic                            wb_we_i,
  input logic                            wb_stb_i,
  input logic                            wb_cyc_i,
  input logic                            wb_ack_o,
  input logic [7:0]                      lcr,
  input logic [`UART_FIFO_COUNTER_W-1:0] rf_count
);

  default clocking cb @(posedge wb_clk_i); endclocking
  default disable iff (wb_rst_i);

  // Máximo de ciclos entre stb y ack
  localparam int unsigned ACK_MAX = 4;

  int unsigned n_fail = 0;       // aserciones falladas

  function automatic void rep_err(string id, string msg);
    n_fail++;
`ifdef UART_SVA_NO_UVM
    $display("[SVA_FAIL] %s: %s (t=%0t)", id, msg, $time);
`else
    uvm_pkg::uvm_report_error(id, msg, uvm_pkg::UVM_NONE);
`endif
  endfunction

  wire req = wb_cyc_i && wb_stb_i;   // hay un acceso en curso

  // A-WB-01
  property p_wb01_stable;
    (req && !wb_ack_o) |=>
      (wb_cyc_i && wb_stb_i && $stable(wb_adr_i) && $stable(wb_we_i) && $stable(wb_sel_i) &&
       (!wb_we_i || $stable(wb_dat_i)));
  endproperty
  a_wb01_stable: assert property (p_wb01_stable)
    else rep_err("A-WB-01", "cambió la transferencia");
  c_wb01_wait:   cover property (req && !wb_ack_o ##1 req && !wb_ack_o ##1 wb_ack_o);
  c_wb01_wr:     cover property (req && wb_we_i && !wb_ack_o ##1 wb_ack_o);
  c_wb01_rd:     cover property (req && !wb_we_i && !wb_ack_o ##1 wb_ack_o);

  // A-WB-02: 
  property p_wb02_ack;
    (req && !wb_ack_o) |-> ##[1:ACK_MAX] wb_ack_o;
  endproperty
  a_wb02_ack: assert property (p_wb02_ack)
    else rep_err("A-WB-02", $sformatf("sin ack en %0d ciclos", ACK_MAX));
  c_wb02_ack2: cover property ((req && !wb_ack_o) [*2] ##1 wb_ack_o);   // la latencia normal del RTL

  // A-WB-03: 
  a_wb03_one: assert property (wb_ack_o |=> !wb_ack_o)
    else rep_err("A-WB-03", "ack dura más de un ciclo");
  a_wb03_req: assert property (wb_ack_o |-> req)
    else rep_err("A-WB-03", "ack sin cyc y stb activos");
  c_wb03_ack: cover property (req && wb_ack_o ##1 !wb_ack_o);

  // A-WB-04: 
  a_wb04_ctl: assert property (!$isunknown({wb_cyc_i, wb_stb_i, wb_we_i, wb_adr_i, wb_sel_i}))
    else rep_err("A-WB-04", "cyc, stb, we, adr o sel tienen X o Z");
  a_wb04_ack: assert property (!$isunknown(wb_ack_o))
    else rep_err("A-WB-04", "wb_ack_o tiene X o Z");


`ifdef DATA_BUS_WIDTH_8
  wire [2:0] word = wb_adr_i[2:0];
`else
  wire [2:0] word = wb_adr_i[4:2];
`endif
  wire rbr_rd_empty = req && !wb_we_i && word == 3'd0 && !lcr[7] && rf_count == '0;
  logic rbr_empty_seen;
  always_ff @(posedge wb_clk_i or posedge wb_rst_i) begin
    if (wb_rst_i)        rbr_empty_seen <= 1'b0;
    else if (!req)       rbr_empty_seen <= 1'b0;
    else if (rbr_rd_empty) rbr_empty_seen <= 1'b1;
  end

  // Solo lecturas
  property p_wb04_dat;
    (wb_ack_o && !wb_we_i && !rbr_empty_seen && !rbr_rd_empty) |-> !$isunknown(wb_dat_o);
  endproperty
  a_wb04_dat: assert property (p_wb04_dat)
    else rep_err("A-WB-04", "wb_dat_o tiene X o Z en una lectura con ack");
  c_wb04_full: cover property (wb_ack_o && !wb_we_i && !$isunknown({wb_adr_i, wb_sel_i, wb_dat_o}));
  c_wb04_rbr_empty: cover property (wb_ack_o && rbr_empty_seen);   // el caso que se excluye sí ocurre

  // A-WB-05
`ifndef DATA_BUS_WIDTH_8
  wire sel_bad = !$onehot(wb_sel_i) && !(wb_sel_i == 4'b1111 && word >= 3'd2);

  property p_wb05_bad_sel;
    (req && sel_bad && !wb_ack_o) |-> ##[1:ACK_MAX] wb_ack_o;
  endproperty
  a_wb05_bad_sel: assert property (p_wb05_bad_sel)
    else rep_err("A-WB-05", $sformatf("acceso con sel = %b sin ack", wb_sel_i));
  c_wb05_zero: cover property (req && wb_sel_i == 4'b0000 && !wb_ack_o ##[1:ACK_MAX] wb_ack_o);
  c_wb05_two:  cover property (req && ($countones(wb_sel_i) == 2) && !wb_ack_o ##[1:ACK_MAX] wb_ack_o);
  c_wb05_f_8bit: cover property (req && wb_sel_i == 4'b1111 && word < 3'd2 && !wb_ack_o ##[1:ACK_MAX] wb_ack_o);
`endif

endmodule : uart_wb_sva
