//////////////////////////////////////////////////////////////////////
// uart_virtual_sequencer:
// Donde corre la secuencia principal. No maneja transacciones propias:
// guarda los secuenciadores de los tres agentes, el RAL y la configuración.
// uart_env llena las referencias en connect_phase y las secuencias las usan por p_sequencer.
//////////////////////////////////////////////////////////////////////

class uart_virtual_sequencer extends uvm_sequencer; // creacion de sequencer a partir de uvm
  `uvm_component_utils(uart_virtual_sequencer)

  uvm_sequencer #(wb_item)  wb_sqr;
  uvm_sequencer #(ser_item) ser_sqr;
  uvm_sequencer #(mdm_item) mdm_sqr;
  uart_reg_block            regm;
  uart_env_cfg              cfg;

  // Estado compartido por las actividades que corren en paralelo
  semaphore bus_sem;       // una actividad a la vez en el bus: quien pone DLAB = 1 o cambia LCR lo guarda toda la ventana, así nadie escribe THR cuando en realidad sería DLL
  bit       traffic_done;  // TX, RX, módem y eventos terminaron
  bit       rst_hit;       // hubo reset en este episodio: todas las actividades cortan
  int       episode;       // número del episodio en curso, para los mensajes

  function new(string name, uvm_component parent); // constructor
    super.new(name, parent);
    bus_sem = new(1);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(uart_env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("NOCFG", "No se encontró env_cfg en uvm_config_db")
  endfunction
endclass : uart_virtual_sequencer