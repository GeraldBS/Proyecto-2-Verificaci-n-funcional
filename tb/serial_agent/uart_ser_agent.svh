

class uart_ser_agent extends uvm_agent;



  // Registro en la Factory
  `uvm_component_utils(uart_ser_agent)

  // handles a los subcomponentes del agente
  ser_driver      driver;
  ser_sequencer   sequencer;
  ser_rx_monitor  srx_mon;
  ser_tx_monitor  stx_mon;

  // handle a la configuración del agente (publicada por el test)
  uart_ser_agent_cfg cfg;

  // Constructor estándar de UVM
  function new(string name = "uart_ser_agent", uvm_component parent);
    super.new(name, parent);
  endfunction

  //  Instanciación de componentes
 
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    // Obtenemos la configuración del agente (donde viene is_active)
    if (!uvm_config_db#(uart_ser_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("NO_CFG", {"Falta uart_ser_agent_cfg para ", get_full_name()})
    end

    
    srx_mon = ser_rx_monitor::type_id::create("srx_mon", this);
    stx_mon = ser_tx_monitor::type_id::create("stx_mon", this);

    // El driver y el sequencer SOLO se instancian si el agente es ACTIVO
    if (cfg.is_active == UVM_ACTIVE) begin
      sequencer = ser_sequencer::type_id::create("sequencer", this);
      driver    = ser_driver::type_id::create("driver", this);
    end
  endfunction


  // Unir el driver con el sequencer
 
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Solo conectamos el puerto de ítems si somos un agente ACTIVO (y existen ambos)
    if (cfg.is_active == UVM_ACTIVE) begin
      // Conexión TLM estándar de UVM: puerto_del_driver -> export_del_sequencer
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
    
    class uart_ser_agent extends uvm_agent;

  // Registro en la Factory de UVM
  `uvm_component_utils(uart_ser_agent)

  // 1. Asas (handles) a los subcomponentes del agente
  ser_driver      driver;
  ser_sequencer   sequencer;
  ser_rx_monitor  srx_mon;
  ser_tx_monitor  stx_mon;

  // Asa para el objeto de configuración (para saber si somos UVM_ACTIVE o UVM_PASSIVE)
  uart_ser_agent_cfg cfg;

  // Constructor estándar de UVM
  function new(string name = "uart_ser_agent", uvm_component parent);
    super.new(name, parent);
  endfunction

  // ------------------------------------------------------------------------
  // Fase de Construcción (build_phase): Instanciación de componentes
  // ------------------------------------------------------------------------
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    // Obtenemos la configuración del agente (donde viene is_active)
    if (!uvm_config_db#(uart_ser_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("NO_CFG", {"Falta uart_ser_agent_cfg para ", get_full_name()})
    end

    // Los monitores SIEMPRE se instancian, sin importar si el agente es activo o pasivo
    srx_mon = ser_rx_monitor::type_id::create("srx_mon", this);
    stx_mon = ser_tx_monitor::type_id::create("stx_mon", this);

    // El driver y el sequencer SOLO se instancian si el agente es ACTIVO
    if (cfg.is_active == UVM_ACTIVE) begin
      sequencer = ser_sequencer::type_id::create("sequencer", this);
      driver    = ser_driver::type_id::create("driver", this);
    end
  endfunction

  // ------------------------------------------------------------------------
  // Fase de Conexión (connect_phase): Unir el driver con el sequencer
  // ------------------------------------------------------------------------
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Solo conectamos el puerto de ítems si somos un agente ACTIVO (y existen ambos)
    if (cfg.is_active == UVM_ACTIVE) begin
      // Conexión TLM estándar de UVM: puerto_del_driver -> export_del_sequencer
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
    
    // (Nota: Los analysis_ports de srx_mon y stx_mon quedan libres aquí. 
    // Será el entorno (uart_env) el encargado de conectarlos al Scoreboard.)
  endfunction

endclass : uart_ser_agent
  endfunction

endclass : uart_ser_agent