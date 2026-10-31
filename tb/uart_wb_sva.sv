// -----------------------------------------------------------------------------
// uart_wb_sva.sv
// Ejemplo mínimo de un módulo de aserciones que se enlaza (bind) a uart_top.
//
// Solo muestra el mecanismo: puertos de entrada con los mismos nombres que
// las señales del DUT, propiedades con su cover, y el bind en tb_top.sv.
// El conjunto completo de aserciones de interfaz es parte del proyecto.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`include "uart_defines.v"

module uart_wb_sva (
  input logic                         wb_clk_i,
  input logic                         wb_rst_i,
  input logic [`UART_ADDR_WIDTH-1:0]  wb_adr_i,
  input logic [`UART_DATA_WIDTH-1:0]  wb_dat_i,
  input logic [3:0]                   wb_sel_i,
  input logic                         wb_we_i,
  input logic                         wb_stb_i,
  input logic                         wb_cyc_i,
  input logic                         wb_ack_o
);

  default clocking cb @(posedge wb_clk_i); endclocking
  default disable iff (wb_rst_i);

  // Ejemplo 1 (lado del maestro): mientras el maestro espera ack,
  // dirección, sentido, selección y dato de escritura no cambian.
  property p_master_stable;
    (wb_cyc_i && wb_stb_i && !wb_ack_o) |=>
      (wb_stb_i && $stable(wb_adr_i) && $stable(wb_we_i) && $stable(wb_sel_i) &&
       (!wb_we_i || $stable(wb_dat_i)));
  endproperty
  a_master_stable: assert property (p_master_stable)
    else $error("Wishbone: el maestro cambió la transferencia antes de recibir ack");
  c_master_wait:   cover  property (wb_cyc_i && wb_stb_i && !wb_ack_o ##1 wb_ack_o);

  // Ejemplo 2 (lado del DUT): ack nunca es X fuera de reset.
  a_ack_known: assert property (!$isunknown(wb_ack_o))
    else $error("Wishbone: wb_ack_o tiene X o Z");

endmodule : uart_wb_sva
