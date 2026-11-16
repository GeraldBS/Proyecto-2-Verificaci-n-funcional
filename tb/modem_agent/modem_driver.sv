class modem_driver extends uvm_driver #(mdm_item);

  `uvm_component_utils(modem_driver) //Macro de registro en la Factory

  modem_agent_cfg cfg;

  //Constructor
  function new(string name = "modem_driver", uvm_component parent);
    super.new(name, parent);
  endfunction

    // Fase de construcción: obtener la configuración del agente
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    // Obtener interfaz y configuracion
    if (!uvm_config_db#(modem_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("NO_CFG", {"Falta modem_agent_cfg para ", get_full_name()})
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    // Estado inicial de las lineas (reposo en alto)
    cfg.vif.cts <= 1'b1;
    cfg.vif.dsr <= 1'b1;
    cfg.vif.ri  <= 1'b1;
    cfg.vif.dcd <= 1'b1;

    forever begin
      seq_item_port.get_next_item(req);

      // Aplicar retardo antes de cambiar el estado
      if (req.gap_cycles > 0) begin
        repeat(req.gap_cycles) @(posedge cfg.vif.clk);
      end

      // Invertir senales segun la mascara 'toggle'
      if (req.toggle[0]) cfg.vif.cts <= ~cfg.vif.cts;
      if (req.toggle[1]) cfg.vif.dsr <= ~cfg.vif.dsr;
      if (req.toggle[2]) cfg.vif.ri  <= ~cfg.vif.ri;
      if (req.toggle[3]) cfg.vif.dcd <= ~cfg.vif.dcd;

      // Esperar un ciclo para que el hardware registre los cambios
      @(posedge cfg.vif.clk);

      seq_item_port.item_done();
    end
  endtask

endclass : modem_driver