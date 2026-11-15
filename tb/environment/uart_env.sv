//////////////////////////////////////////////////////////////////////
// uart_env: ambiente de verificación                              
// Crea los tres agentes, el modelo de registros con su adaptador y
// predictor, el scoreboard, la cobertura y el secuenciador virtual, y
// hace todas las conexiones
//////////////////////////////////////////////////////////////////////

class uart_env extends uvm_env;
  `uvm_component_utils(uart_env) // component_utils dado que son componentes

  uart_env_cfg        cfg;       // configuración de la prueba
  uart_wb_agent       wb_agt;    // agente Wishbone 
  uart_ser_agent      ser_agt;   // agente serie (dispositivo remoto)
  modem_agent         mdm_agt;   // agente de módem
  uart_reg_block      mod_reg;   // modelo de registros
  uart_reg_adapter    adapter;   // accesos del RAL a wb_item
  uart_reg_predictor  predictor; // actualiza el espejo con lo que ve el monitor
  uart_scoreboard     scb;       // modelo de referencia y comparación
  uart_cov            cov;       // cobertura funcional
  uart_virtual_sequencer vsqr;   // donde corre uart_main_vseq

  // Constructor
  function new(string name = "env", uvm_component parent = null); // coincide en ser conmponente
    super.new(name, parent);
  endfunction

  // Crea los componentes y el modelo de registros
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(uart_env_cfg)::get(this, "", "env_cfg", cfg))   // la publica uart_base_test
      `uvm_fatal("NOCFG", "uart_env:  env_cfg no está en uvm_config_db")   // error fatal sin configuración

    wb_agt    = uart_wb_agent::type_id::create("wb_agt", this);   // crea el objeto con factory
    ser_agt   = uart_ser_agent::type_id::create("ser_agt", this);
    mdm_agt   = modem_agent::type_id::create("mdm_agt", this);
    scb       = uart_scoreboard::type_id::create("scb", this);
    cov       = uart_cov::type_id::create("cov", this);
    vsqr      = uart_virtual_sequencer::type_id::create("vsqr", this);
    predictor = uart_reg_predictor::type_id::create("predictor", this);

    // El modelo de registros no es un componente por lo que se crea y se construye aquí
    mod_reg = uart_reg_block::type_id::create("mod_reg");
    mod_reg.build();   // registros, mapas DLAB = 0 y DLAB = 1 y rutas de puerta trasera
    mod_reg.reset();   // espejo con los valores de reset
    mod_reg.set_test_exclusions();   // registros que las secuencias integradas deben saltar
    adapter = uart_reg_adapter::type_id::create("adapter"); // no es componente, se crea y se construye aquí
  endfunction

  // Conecta el RAL, los puertos de análisis y el secuenciador virtual
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // RAL: puerta delantera por el secuenciador Wishbone, predicción explícita.
    mod_reg.dlab0_map.set_sequencer     (wb_agt.sqr, adapter);
    mod_reg.dlab1_map.set_sequencer     (wb_agt.sqr, adapter);
    mod_reg.dlab0_map.set_auto_predict  (0);
    mod_reg.dlab1_map.set_auto_predict  (0);

    predictor.map     = mod_reg.dlab0_map;   
    predictor.regm    = mod_reg;
    predictor.adapter = adapter;

    // Wishbone
    wb_agt.ap.connect     (predictor.bus_in);
    wb_agt.ap.connect     (scb.wb_imp);
    wb_agt.rst_ap.connect (scb.rst_imp);
    wb_agt.int_ap.connect (scb.int_imp);
    wb_agt.ap.connect     (cov.wb_imp);
    wb_agt.int_ap.connect (cov.int_imp);

    // Serie y módem  
    ser_agt.tx_ap.connect (scb.tx_imp);
    ser_agt.rx_ap.connect (scb.rx_imp);
    mdm_agt.ap.connect    (scb.mdm_imp);
    ser_agt.tx_ap.connect (cov.tx_imp);
    ser_agt.rx_ap.connect (cov.rx_imp);
    mdm_agt.ap.connect    (cov.mdm_imp);

    // Cobertura
    scb.ap.connect(cov.evt_imp);

    // Secuenciador virtual (la configuración la obtiene él mismo de la config_db)
    vsqr.wb_sqr  = wb_agt.sqr;
    vsqr.ser_sqr = ser_agt.sqr;
    vsqr.mdm_sqr = mdm_agt.sqr;
    vsqr.regm    = mod_reg;
  endfunction
endclass : uart_env
