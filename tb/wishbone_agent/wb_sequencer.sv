//////////////////////////////////////////////////////////////////////////////////
// wb_sequencer.sv
// Secuenciador del agente Wishbone.
// La cola y el arbitraje de wb_item hacia el driver los hereda de uvm_sequencer.
// Aquí solo guarda cfg y reenvía el reset asíncrono al driver.
//////////////////////////////////////////////////////////////////////////////////

class wb_sequencer extends uvm_sequencer #(wb_item);
  `uvm_component_utils(wb_sequencer)   // registra la clase en la factory

  wb_agent_cfg cfg;     // knobs del agente 
  wb_driver    drv;     // lo asigna wb_agent en connect_phase

  // Constructor
  function new(string name = "wb_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // Obtiene wb_agent_cfg
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(wb_agent_cfg)::get(this, "", UART_KEY_CFG, cfg))   // busca la configuración publicada por el test
      `uvm_fatal("NOCFG", "wb_sequencer: wb_agent_cfg no se encontro en uvm_config_db")   // Error fatal 
  endfunction

  // Reset asíncrono 
  task async_reset(int unsigned width_cycles, real phase_ns);
    if (drv == null)   // agente pasivo: no hay driver
      `uvm_fatal("NODRV", "no hay driver")   // error fatal
    drv.apply_async_reset(width_cycles, phase_ns);
  endtask
endclass : wb_sequencer
