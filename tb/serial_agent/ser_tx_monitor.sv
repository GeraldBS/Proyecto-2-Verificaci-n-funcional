class ser_tx_monitor extends uvm_monitor;

  // Registro en la Factory 
  `uvm_component_utils(ser_tx_monitor)

  // puerto de salida 
  uvm_analysis_port #(ser_item) tx_ap;

  
  uart_ser_agent_cfg cfg;

  // Constructor
  function new(string name = "ser_tx_monitor", uvm_component parent);
    super.new(name, parent);
    tx_ap = new("tx_ap", this); // Inicializamos el puerto de análisis
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
    
      // Como estamos monitoreando lo que sale del DUT, escuchamos stx
      @(negedge cfg.vif.stx);

      // Calculamos el tiempo base de un bit según la configuración de la línea
      bit_ticks = cfg.line.bit_cycles();

      // Muestrear a la mitad del bit para confirmar que es un Start Bit real y no un glitch
      repeat(bit_ticks / 2) @(posedge cfg.vif.clk);
      
      if (cfg.vif.stx !== 1'b0) begin
        continue; 
      end

      // Es un inicio válido. Creamos un nuevo paquete (ser_item) para guardar lo que veamos.
      observed_item = ser_item::type_id::create("observed_item");
      observed_item.dir = SER_DIR_TX; // Marcamos que lo vimos saliendo del DUT
      observed_item.err = SER_OK;     // Asumimos que todo está bien inicialmente
      shift_reg = 8'h00;

      // Nos movemos a la mitad del primer bit de datos
      repeat(bit_ticks) @(posedge cfg.vif.clk);

      // Muestreo de los bits de datos
      for (int i = 0; i < cfg.line.data_bits(); i++) begin
        shift_reg[i] = cfg.vif.stx;
        repeat(bit_ticks) @(posedge cfg.vif.clk); // Saltar a la mitad del siguiente bit
      end
      observed_item.data = shift_reg;

      // Muestreo del bit de paridad (si está habilitada en cfg.line)
      if (cfg.line.pen) begin
        sampled_parity = cfg.vif.stx;
        
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
      if (cfg.vif.stx == 1'b0) begin
        observed_item.err = SER_FRAME;
      end

      // Enviar el paquete observado al Scoreboard y a los colectores de cobertura
      tx_ap.write(observed_item);
    end
  endtask

endclass : ser_tx_monitor