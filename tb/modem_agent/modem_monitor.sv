class modem_monitor extends uvm_monitor;

  `uvm_component_utils(modem_monitor) //Macro de registro en la Factory

  // Puerto de analisis para enviar transacciones al scoreboard y cobertura
  uvm_analysis_port #(mdm_item) ap;

  modem_agent_cfg cfg;

  function new(string name = "modem_monitor", uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if (!uvm_config_db#(modem_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("NO_CFG", {"Falta modem_agent_cfg para ", get_full_name()})
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    mdm_item item;
    
    // Variables locales para detectar flancos (cambios de estado)
    bit [3:0] prev_in_val;
    bit       prev_rts;
    bit       prev_dtr;

    // Sincronizacion inicial
    @(posedge cfg.vif.clk);
    prev_in_val = {cfg.vif.dcd, cfg.vif.ri, cfg.vif.dsr, cfg.vif.cts};
    prev_rts    = cfg.vif.rts;
    prev_dtr    = cfg.vif.dtr;

    forever begin
      @(posedge cfg.vif.clk);

      // Evaluar si alguna de las 6 senales del modem cambio
      if ({cfg.vif.dcd, cfg.vif.ri, cfg.vif.dsr, cfg.vif.cts} !== prev_in_val || 
          cfg.vif.rts !== prev_rts || 
          cfg.vif.dtr !== prev_dtr) begin
        
        item = mdm_item::type_id::create("item");
        
        // Mapeo de bits: 0=CTS, 1=DSR, 2=RI, 3=DCD
        item.in_val = {cfg.vif.dcd, cfg.vif.ri, cfg.vif.dsr, cfg.vif.cts};
        
        // El operador XOR detecta exactamente cuales bits cambiaron
        item.in_chg = item.in_val ^ prev_in_val; 
        
        item.rts    = cfg.vif.rts;
        item.dtr    = cfg.vif.dtr;

        // Emitir la transaccion capturada
        ap.write(item);

        // Actualizar el estado previo para la siguiente iteracion
        prev_in_val = item.in_val;
        prev_rts    = item.rts;
        prev_dtr    = item.dtr;
      end
    end
  endtask

endclass : modem_monitor