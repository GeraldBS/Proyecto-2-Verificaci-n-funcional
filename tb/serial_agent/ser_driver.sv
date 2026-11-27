class ser_driver extends uvm_driver #(ser_item);

    //Factory registration
    `uvm_component_utils(ser_driver)

    uart_ser_agent_cfg cfg; // Configuración del agente

    //Connstructor
    function new(string name = "ser_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //obtener la configuración del ambiente 

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(uart_ser_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("SER_DRV_CFG", "No se pudo obtener la configuración del agente")
    endfunction

    //Bucle principal de inyeccion de trafico

    virtual task run_phase(uvm_phase phase);
        cfg.vif.srx = 1'b1; // Inicializar la línea de recepción en alto
        forever begin
            seq_item_port.get_next_item(req);

            if (cfg.loopback == 1'b1) begin
                // En loopback, simulamos el tiempo de espera pero no inyectamos nada físico
                repeat(cfg.line.tc_cycles()) @(posedge cfg.vif.clk); 
            end else begin
                // Transmitimos el paquete físico
                drive_item(req);
            end

            seq_item_port.item_done();
        end
    endtask

    //Tarea para inyectar el item en la línea serial

    virtual task drive_item(ser_item item);
    int bit_ticks;
    int parity_calc;

    // Calcular la duración real del bit (16 * DL ciclos, ajustado por baud_dev) baud_dev viene en décimas de % (ej. 25 = 2.5%). 
    bit_ticks = cfg.line.bit_cycles();
    if (item.baud_dev != 0) begin
      bit_ticks = bit_ticks + (bit_ticks * item.baud_dev / 1000); 
    end

    // Aplicar el Gap 
    repeat(item.gap_bits * bit_ticks) @(posedge cfg.vif.clk);

    //Manejo de glitch
    if (item.err == SER_GLITCH) begin
      cfg.vif.srx = 1'b0; // Baja la línea
      repeat(item.glitch_w * (bit_ticks / 16)) @(posedge cfg.vif.clk); // 1 a 15 dieciseisavos
      cfg.vif.srx = 1'b1; // Vuelve a subir
      repeat(bit_ticks) @(posedge cfg.vif.clk); // si no, con gap 0 el glitch se pega al inicio del siguiente
      return; // El glitch es solo ruido, no envía un carácter real
    end

    //Manejo de break (Línea en 0 todo el tiempo)
    if (item.err == SER_BREAK) begin
      cfg.vif.srx = 1'b0;
      // Duración: el carácter completo + los break_bits extra
      repeat(cfg.line.tc_cycles() + (item.break_bits * bit_ticks)) @(posedge cfg.vif.clk);
      cfg.vif.srx = 1'b1;
      repeat(bit_ticks) @(posedge cfg.vif.clk); // el DUT sale del break solo cuando ve srx en 1
      return;
    end

    // Transmisión de un carácter normal

    //Bit de Inicio 
    cfg.vif.srx = 1'b0;
    repeat(bit_ticks) @(posedge cfg.vif.clk);

    // Bits de Datos (Enviando del LSB al MSB)
    for (int i = 0; i < cfg.line.data_bits(); i++) begin
      cfg.vif.srx = item.data[i];
      repeat(bit_ticks) @(posedge cfg.vif.clk);
    end

    // Bit de Paridad 
    if (cfg.line.pen) begin
      if (cfg.line.sp) begin
        // Paridad forzada (Siempre 0 o Siempre 1)
        parity_calc = ~cfg.line.eps; // Si eps=1, parity=0. Si eps=0, parity=1.
      end else begin
        // Paridad real (Par o Impar calculada sobre los bits de datos usados)
        parity_calc = ^(item.data & ((1 << cfg.line.data_bits()) - 1)); // XOR de los datos
        if (!cfg.line.eps) parity_calc = ~parity_calc; // impar, invertimos (EPS = 1 es par, igual que el RTL)
      end

      // Inyección del error de paridad
      if (item.err == SER_PARITY) begin
        parity_calc = ~parity_calc; // Corrompemos el bit a propósito
      end
      
      cfg.vif.srx = parity_calc;
      repeat(bit_ticks) @(posedge cfg.vif.clk);
    end

    // (Stop Bits)
    // Inyección del error de trama, Manda un 0 en vez de un 1
    if (item.err == SER_FRAME) begin
      cfg.vif.srx = 1'b0;
    end else begin
      cfg.vif.srx = 1'b1;
    end

    // Esperar el tiempo de parada correspondiente
    if (item.short_stop) begin
      repeat(bit_ticks) @(posedge cfg.vif.clk); // Solo 1 bit aunque pidan 1.5 o 2
    end else begin
      repeat(cfg.line.stop_ticks() * (bit_ticks / 16)) @(posedge cfg.vif.clk);
    end

    // Retorno a reposo
    cfg.vif.srx = 1'b1;
    // con la parada en 0 el DUT espera ver srx en 1 para guardar el caracter
    if (item.err == SER_FRAME) repeat(bit_ticks) @(posedge cfg.vif.clk);
  endtask

endclass : ser_driver