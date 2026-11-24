class uart_virtual_sequencer extends uvm_sequencer;
  `uvm_component_utils(uart_virtual_sequencer)

  uvm_sequencer #(wb_item)  wb_sqr;
  uvm_sequencer #(ser_item) ser_sqr;
  uvm_sequencer #(mdm_item) mdm_sqr;
  uart_reg_block            regm;
  uart_env_cfg              cfg;

  semaphore bus_sem;       // si alguien pone DLAB = 1 nadie mas puede escribir THR, seria DLL
  bit       traffic_done;  // TX, RX, módem y eventos terminaron
  bit       rst_hit;       // hubo reset en este episodio: todos cortan
  int       episode;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    bus_sem = new(1);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(uart_env_cfg)::get(this, "", "env_cfg", cfg))
      `uvm_fatal("NOCFG", "No se encontró env_cfg en uvm_config_db")
  endfunction
endclass : uart_virtual_sequencer
