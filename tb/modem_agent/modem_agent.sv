class modem_agent extends uvm_agent;

  //Macros de registro en la Factory
  `uvm_component_utils(modem_agent)

  // Subcomponentes: driver, sequencer y monitor
  modem_driver    driver;
  modem_sequencer sqr;
  modem_monitor   monitor;

  // Puerto de análisis expuesto hacia el exterior
  uvm_analysis_port #(mdm_item) ap;

  // Objeto de configuración para evaluar el modo activo/pasivo
  modem_agent_cfg cfg;

  // Constructor estándar
  function new(string name = "modem_agent", uvm_component parent);
    super.new(name, parent);
  endfunction


  // Fase de Construcción
 
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Obtener la configuración publicada por el test
    if (!uvm_config_db#(modem_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("NO_CFG", {"Falta modem_agent_cfg para ", get_full_name()})
    end

    // instacia del monitor 
    monitor = modem_monitor::type_id::create("monitor", this);

    // El driver y el secuenciador solo se instancian si el agente es activo
    if (cfg.is_active == UVM_ACTIVE) begin
      sqr    = modem_sequencer::type_id::create("sqr", this);
      driver = modem_driver::type_id::create("driver", this);
    end
  endfunction

  
  // Fase de Conexión
 
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Exponer el puerto del monitor al nivel del agente
    ap = monitor.ap;

    // Conectar driver y sequencer mediante puertos TLM estándar si es activo
    if (cfg.is_active == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sqr.seq_item_export);
    end
  endfunction

endclass : modem_agent