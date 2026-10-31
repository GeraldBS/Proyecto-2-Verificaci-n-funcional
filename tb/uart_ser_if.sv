// -----------------------------------------------------------------------------
// uart_ser_if.sv
// Interfaz de la línea serie del UART.
//
//   stx  : salida serie del DUT   (stx_pad_o)  -> la observa el monitor TX
//   srx  : entrada serie del DUT  (srx_pad_i)  -> la maneja el driver serie
//   baud : salida opcional 16x baud (baud_o), solo con UART_HAS_BAUDRATE_OUTPUT
//
// La línea es asíncrona: el driver y los monitores cuentan ciclos de clk
// para medir el ancho de bit (16 x DL ciclos por bit). El clocking block
// solo se usa para muestrear y manejar sin carreras.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

interface uart_ser_if (input logic clk);

  logic stx;
  logic srx;
  logic baud;

  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output srx;
    input  stx;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input stx, srx, baud;
  endclocking

  modport drv (clocking drv_cb);
  modport mon (clocking mon_cb);

endinterface : uart_ser_if
