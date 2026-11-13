//////////////////////////////////////////////////////////////////////////////////
// wb_agent.sv
// Si wb_agent_cfg.is_active es UVM_PASSIVE solo crea los monitores.
//////////////////////////////////////////////////////////////////////////////////

class uart_wb_agent extends uvm_agent;
  `uvm_component_utils(uart_wb_agent)   // registra en factory

  wb_agent_cfg      cfg;   // knobs del agente
  wb_sequencer      sqr;   // lleva los items al driver
  wb_driver         drv;   // maestro Wishbone
  wb_monitor        mon;   // observa accesos
  uart_int_monitor  int_mon;   // observa int_o

  uvm_analysis_port #(wb_item)       ap;   // accesos terminados
  uvm_analysis_port #(wb_rst_item)   rst_ap;   // eventos de reset
  uvm_analysis_port #(uart_int_item) int_ap;   // flancos de int_o

  // Constructor
  function new(string name = "wb_agt", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // Obtiene la configuración y crea los componentes (driver y sequencer solo si es activo)
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(wb_agent_cfg)::get(this, "", UART_KEY_CFG, cfg))   
      `uvm_fatal("NOCFG", "no se encontró wb_agent_cfg en uvm_config_db")   // error 
    is_active = cfg.is_active;   // activo o pasivo según la configuración

    mon     = wb_monitor::type_id::create("mon", this);   // crea el objeto con factory
    int_mon = uart_int_monitor::type_id::create("int_mon", this);   // crea el objeto con factory
    if (is_active == UVM_ACTIVE) begin
      sqr = wb_sequencer::type_id::create("sqr", this);   // crea el objeto con factory
      drv = wb_driver::type_id::create("drv", this);   // crea el objeto con factory
    end

    ap     = new("ap", this);   // crea el puerto de análisis
    rst_ap = new("rst_ap", this);   
    int_ap = new("int_ap", this);   
  endfunction

  // Reenvía los puertos de los monitores y conecta driver con sequencer
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mon.ap.connect(ap);   // reenvía los accesos al puerto del agente
    mon.rst_ap.connect(rst_ap);   // reenvía los resets
    int_mon.ap.connect(int_ap);   // reenvía los flancos de int_o
    if (is_active == UVM_ACTIVE) begin
      drv.seq_item_port.connect(sqr.seq_item_export);   // el driver pide items al sequencer
      sqr.drv = drv;   // el sequencer puede pedirle resets al driver
    end
  endfunction
endclass : uart_wb_agent
