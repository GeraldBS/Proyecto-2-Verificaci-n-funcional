
typedef enum {EV_THR_WRITE, EV_RX_PUSH, EV_RBR_READ, EV_RESET} uart_evt_e;

class uart_model_evt extends uvm_object;

  uart_evt_e   kind;
  int unsigned tx_level;     // Nivel de la FIFO TX antes de la escritura
  int unsigned rx_level;     // Nivel de la FIFO RX antes de empujar o leer
  bit          lost;         // Escritura perdida (TX llena) u overrun (RX llena)
  int unsigned pending_cnt;  // Fuentes de interrupcion pendientes
  bit          tx_busy;
  bit          rx_busy;
  int unsigned rst_cycles;   // Solo aplica para EV_RESET

  // Macros para automatizacion de UVM
  `uvm_object_utils_begin(uart_model_evt)
    `uvm_field_enum(uart_evt_e, kind, UVM_ALL_ON)
    `uvm_field_int(tx_level, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(rx_level, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(lost, UVM_ALL_ON)
    `uvm_field_int(pending_cnt, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(tx_busy, UVM_ALL_ON)
    `uvm_field_int(rx_busy, UVM_ALL_ON)
    `uvm_field_int(rst_cycles, UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "uart_model_evt"); // constructor
    super.new(name);
  endfunction

endclass : uart_model_evt