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
    
    // sacamos la cfg del agente
    if (!uvm_config_db#(uart_ser_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("NO_CFG", {"Falta uart_ser_agent_cfg para ", get_full_name()})
    end
  endfunction

  int unsigned t;        // ciclos desde el flanco de inicio
  int          t_sube;   // primer ciclo en que srx volvio a 1, -1 si todavia no

  // igual que repeat(n) @(posedge clk) pero anotando cuando sube srx
  task avanzar(int unsigned n);
    repeat (n) begin
      @(posedge cfg.vif.clk);
      t++;
      if (t_sube < 0 && cfg.vif.srx === 1'b1) t_sube = t;
    end
  endtask

  // la primera subida tiene que caer en un borde de bit, si no la velocidad viene desviada
  function void medir_baudios(ser_item item, int bit_ticks);
    int k, err_ciclos, desv;
    if (t_sube <= 0) return;   // no subio (break), no hay que medir
    k = (t_sube + bit_ticks / 2) / bit_ticks;
    if (k == 0) k = 1;
    err_ciclos = t_sube - k * bit_ticks;
    if (err_ciclos < 0) err_ciclos = -err_ciclos;
    if (err_ciclos > 0) err_ciclos--;   // un ciclo de gracia porque el driver y nosotros vemos el mismo flanco
    desv = err_ciclos * 1000 / (k * bit_ticks);   // en decimas de %
    if (k == 1 && t_sube < bit_ticks * 85 / 100)
      item.err = SER_GLITCH_START;   // el inicio duro mucho menos de un bit
    else if (desv >= cfg.baud_out_min)
      item.err = SER_BAUD_OUT;
    else if (desv > 0 && item.err == SER_OK)
      item.err = SER_BAUD_IN;
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
      t      = 0;
      t_sube = -1;

      avanzar(bit_ticks / 2);
      
      if (cfg.vif.srx !== 1'b0) begin
        
        continue; 
      end

      observed_item = ser_item::type_id::create("observed_item");
      observed_item.dir = SER_DIR_RX; // Marcamos que lo vimos entrando
      observed_item.err = SER_OK;     // Asumimos que todo está bien inicialmente
      shift_reg = 8'h00;

      
      avanzar(bit_ticks);

      for (int i = 0; i < cfg.line.data_bits(); i++) begin
        shift_reg[i] = cfg.vif.srx;
        avanzar(bit_ticks); // Saltar a la mitad del siguiente bit
      end
      observed_item.data = shift_reg;

      if (cfg.line.pen) begin
        sampled_parity = cfg.vif.srx;
        
        // Calculamos cuál debió ser la paridad correcta para este dato
        if (cfg.line.sp) begin
          calc_parity = ~cfg.line.eps; // Stick parity (fija)
        end else begin
          calc_parity = ^(shift_reg & ((1 << cfg.line.data_bits()) - 1)); // Paridad real
          if (!cfg.line.eps) calc_parity = ~calc_parity;   // impar
        end

        // Si lo que medimos no cuadra con lo calculado, marcamos error de paridad
        if (sampled_parity != calc_parity) begin
          observed_item.err = SER_PARITY;
        end
        
        avanzar(bit_ticks); // Saltar a la mitad del bit de parada
      end

      // Muestreo del primer bit de parada
      if (cfg.vif.srx == 1'b0) begin
        observed_item.err = SER_FRAME;
        // datos, paridad y parada en 0 es un break, el DUT mete un 00 a la FIFO
        if (shift_reg == 8'h00 && !(cfg.line.pen && sampled_parity)) observed_item.err = SER_BREAK;
      end
      medir_baudios(observed_item, bit_ticks);

      rx_ap.write(observed_item);
    end
  endtask

endclass : ser_rx_monitor