class ser_rx_monitor extends uvm_monitor;

  // Registro en la Factory 
  `uvm_component_utils(ser_rx_monitor)


  uvm_analysis_port #(ser_item) rx_ap;


  uart_ser_agent_cfg cfg;

  // Constructor
  function new(string name = "ser_rx_monitor", uvm_component parent);
    super.new(name, parent);
    rx_ap = new("rx_ap", this); // Inicializamos el puerto de análisis
  endfunction


  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    // Obtenemos la maleta de configuración (cfg)
    if (!uvm_config_db#(uart_ser_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("NO_CFG", {"Falta uart_ser_agent_cfg para ", get_full_name()})
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    ser_item  observed_item;
    int       bit_ticks;
    bit [7:0] shift_reg;
    bit       sampled_parity;
    bit       calc_parity;

    forever begin
    
      @(negedge cfg.vif.srx);

      bit_ticks = cfg.line.bit_cycles();

      repeat(bit_ticks / 2) @(posedge cfg.vif.clk);
      
      if (cfg.vif.srx !== 1'b0) begin
        
        continue; 
      end

      observed_item = ser_item::type_id::create("observed_item");
      observed_item.dir = SER_DIR_RX; // Marcamos que lo vimos entrando
      observed_item.err = SER_OK;     // Asumimos que todo está bien inicialmente
      shift_reg = 8'h00;

      
      repeat(bit_ticks) @(posedge cfg.vif.clk);

      for (int i = 0; i < cfg.line.data_bits(); i++) begin
        shift_reg[i] = cfg.vif.srx;
        repeat(bit_ticks) @(posedge cfg.vif.clk); // Saltar a la mitad del siguiente bit
      end
      observed_item.data = shift_reg;

      if (cfg.line.pen) begin
        sampled_parity = cfg.vif.srx;
        
        // Calculamos cuál debió ser la paridad correcta para este dato
        if (cfg.line.sp) begin
          calc_parity = ~cfg.line.eps; // Stick parity (fija)
        end else begin
          calc_parity = ^(shift_reg & ((1 << cfg.line.data_bits()) - 1)); // Paridad real
          if (cfg.line.eps) calc_parity = ~calc_parity;
        end

        // Si lo que medimos no cuadra con lo calculado, marcamos error de paridad
        if (sampled_parity != calc_parity) begin
          observed_item.err = SER_PARITY;
        end
        
        repeat(bit_ticks) @(posedge cfg.vif.clk); // Saltar a la mitad del bit de parada
      end

      // Muestreo del primer bit de parada
      if (cfg.vif.srx == 1'b0) begin
        observed_item.err = SER_FRAME;
      end

      rx_ap.write(observed_item);
    end
  endtask

endclass : ser_rx_monitor