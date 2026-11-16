
class mdm_item extends uvm_sequence_item;

  
  rand bit [3:0]    toggle;      // Indica qué entradas invertir: bit 0 CTS, 1 DSR, 2 RI, 3 DCD
  rand int unsigned gap_cycles;  // Ciclos de espera antes del cambio

  // Variables de estado registradas por el monitor
  bit [3:0]         in_val;      // Estado de CTS, DSR, RI, DCD después del cambio
  bit [3:0]         in_chg;      // Indica cuáles señales cambiaron realmente
  bit               rts;         // Estado de la salida RTS
  bit               dtr;         // Estado de la salida DTR

  // Registro en la Factory y macros de campo para automatización
  `uvm_object_utils_begin(mdm_item)
    `uvm_field_int(toggle,     UVM_ALL_ON)
    `uvm_field_int(gap_cycles, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(in_val,     UVM_ALL_ON)
    `uvm_field_int(in_chg,     UVM_ALL_ON)
    `uvm_field_int(rts,        UVM_ALL_ON)
    `uvm_field_int(dtr,        UVM_ALL_ON)
  `uvm_object_utils_end

  // Constructor estándar de UVM
  function new(string name = "mdm_item");
    super.new(name);
  endfunction

endclass : mdm_item