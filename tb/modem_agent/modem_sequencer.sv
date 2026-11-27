
class modem_sequencer extends uvm_sequencer #(mdm_item); // hereda de uvm

  `uvm_component_utils(modem_sequencer) //Macro de registro en la Factory

    // Constructor 
  function new(string name = "modem_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass : modem_sequencer