

class ser_sequencer extends uvm_sequencer #(ser_item);

  // Registro en la Factory de UVM
  `uvm_component_utils(ser_sequencer)

  // Constructor 
  // Se inicializa utilizando el nombre de la instancia y el handle hacia el padre jerárquico.
  function new(string name = "ser_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

endclass : ser_sequencer