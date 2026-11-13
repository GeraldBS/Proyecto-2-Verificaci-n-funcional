// Lista de archivos para VCS. Las rutas son relativas al directorio sim/.
// uart_defines.v y timescale.v no se listan: los incluyen los propios archivos
// (por eso hace falta +incdir+../rtl).

+incdir+../rtl
+incdir+../tb
+incdir+../tests

// ---- RTL del DUT (no modificar) ----
../rtl/raminfr.v
../rtl/uart_sync_flops.v
../rtl/uart_tfifo.v
../rtl/uart_rfifo.v
../rtl/uart_transmitter.v
../rtl/uart_receiver.v
../rtl/uart_regs.v
../rtl/uart_debug_if.v
../rtl/uart_wb.v
../rtl/uart_top.v

// ---- Interfaces y aserciones ----
../tb/interfaces/wb_if.sv
../tb/interfaces/uart_ser_if.sv
../tb/interfaces/modem_if.sv
../tb/assertions/uart_wb_sva.sv

// ---- Ambiente UVM (agreguen aquí sus paquetes, antes de tb_top) ----
../tb/uart_hello_pkg.sv
../tb/uart_pkg.sv

// ---- Top ----
../tb/tb_top.sv
