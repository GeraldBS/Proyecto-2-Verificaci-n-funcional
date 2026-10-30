// -----------------------------------------------------------------------------
// modem_if.sv
// Señales de control de módem del UART.
//
//   Salidas del DUT : rts (rts_pad_o), dtr (dtr_pad_o)
//   Entradas del DUT: cts (cts_pad_i), dsr (dsr_pad_i), ri (ri_pad_i), dcd (dcd_pad_i)
//
// La polaridad de estas señales respecto a MCR y MSR es uno de los puntos
// que el plan de pruebas debe aclarar (sección 3.5 del enunciado).
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

interface modem_if (input logic clk);

  logic rts;
  logic dtr;
  logic cts;
  logic dsr;
  logic ri;
  logic dcd;

  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output cts, dsr, ri, dcd;
    input  rts, dtr;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input rts, dtr, cts, dsr, ri, dcd;
  endclocking

  modport drv (clocking drv_cb);
  modport mon (clocking mon_cb);

endinterface : modem_if
