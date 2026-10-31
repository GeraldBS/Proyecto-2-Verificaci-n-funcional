// -----------------------------------------------------------------------------
// wb_if.sv
// Interfaz Wishbone entre el ambiente UVM y el esclavo uart_top.
//
// Nombres desde el punto de vista del bus:
//   dat_m2s : dato del maestro (ambiente) hacia el esclavo (DUT)  -> wb_dat_i
//   dat_s2m : dato del esclavo (DUT) hacia el maestro (ambiente)  -> wb_dat_o
//
// Los anchos salen de uart_defines.v, de modo que la misma interfaz sirve
// para el bus de 32 bits (por defecto) y para +define+DATA_BUS_WIDTH_8.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`include "uart_defines.v"

interface wb_if (input logic clk);

  logic                         rst;      // reset asíncrono, activo en alto
  logic [`UART_ADDR_WIDTH-1:0]  adr;
  logic [`UART_DATA_WIDTH-1:0]  dat_m2s;
  logic [`UART_DATA_WIDTH-1:0]  dat_s2m;
  logic [3:0]                   sel;
  logic                         we;
  logic                         stb;
  logic                         cyc;
  logic                         ack;
  logic                         irq;      // int_o del DUT

  // Clocking block del driver: maneja las señales del maestro un poco
  // después del flanco y muestrea las respuestas justo antes del flanco.
  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output adr, dat_m2s, sel, we, stb, cyc;
    input  dat_s2m, ack, irq;
  endclocking

  // Clocking block del monitor: solo observa.
  clocking mon_cb @(posedge clk);
    default input #1step;
    input rst, adr, dat_m2s, dat_s2m, sel, we, stb, cyc, ack, irq;
  endclocking

  modport drv (clocking drv_cb, input rst);
  modport mon (clocking mon_cb);

endinterface : wb_if
