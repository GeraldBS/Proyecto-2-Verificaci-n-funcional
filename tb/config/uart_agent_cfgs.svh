//////////////////////////////////////////////////////////////////////
// uart_agent_cfgs: objetos de configuración de agentes, scb y cov  //
//////////////////////////////////////////////////////////////////////
// Solo guardan knobs y la interfaz virtual. Los valores los pone
// uart_env_cfg::parse_plusargs() y la prueba los publica en
// uvm_config_db (tabla 9.3 del plan). Nadie más lee plusargs.
//////////////////////////////////////////////////////////////////////

// ---------------------------------------------------------------- Wishbone
class wb_agent_cfg extends uvm_object;
  `uvm_object_utils(wb_agent_cfg)
  virtual wb_if          vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  // los usa el driver para separar y retrasar transacciones
  int unsigned gap_max       = 4;
  int unsigned gap_zero_pct  = 60;
  int unsigned stb_delay_pct = 20;
  int unsigned stb_delay_max = 3;
  // lo usa la secuencia de ruido para pedir un wb_sel_i inválido (AMB-05)
  int unsigned bad_sel_pct   = 1;

  function new(string name = "wb_agent_cfg");
    super.new(name);
  endfunction
endclass : wb_agent_cfg

// ---------------------------------------------------------------- serie
class uart_ser_agent_cfg extends uvm_object;
  `uvm_object_utils(uart_ser_agent_cfg)
  virtual uart_ser_if    vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  // formato vigente: es la misma referencia que tiene uart_env_cfg,
  // así el driver y los monitores siguen cada reconfiguración
  uart_line_cfg line;
  // en loopback el DUT ignora srx; el driver lo deja en reposo
  bit           loopback;

  // tráfico de recepción (los usa la secuencia RX para llenar ser_item)
  int unsigned rx_chars_max    = 40;
  int unsigned slow_dl         = 256;
  int unsigned slow_chars_max  = 2;
  int unsigned rx_gap_max      = 80;          // bits
  int unsigned rx_gap_w[]      = '{60, 30, 10};  // 0, 1-15 bits, 16-max bits
  int unsigned parity_err_pct  = 5;
  int unsigned frame_err_pct   = 5;
  int unsigned break_pct       = 3;
  int unsigned break_extra_max = 2;           // Tc
  int unsigned glitch_pct      = 3;
  int unsigned glitch_w_max    = 15;          // dieciseisavos de bit
  int unsigned baud_in_pct     = 10;
  int unsigned baud_in_max     = 25;          // décimas de %
  int unsigned baud_out_pct    = 2;
  int unsigned baud_out_min    = 50;
  int unsigned baud_out_max    = 100;
  int unsigned short_stop_pct  = 5;

  function new(string name = "uart_ser_agent_cfg");
    super.new(name);
  endfunction
endclass : uart_ser_agent_cfg

// ---------------------------------------------------------------- módem
class modem_agent_cfg extends uvm_object;
  `uvm_object_utils(modem_agent_cfg)
  virtual modem_if       vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  int unsigned changes_max = 8;
  int unsigned sig_w[]     = '{1, 1, 1, 1};   // CTS, DSR, RI, DCD
  int unsigned gap_max     = 4;               // Tc
  int unsigned multi_pct   = 10;

  function new(string name = "modem_agent_cfg");
    super.new(name);
  endfunction
endclass : modem_agent_cfg

// ---------------------------------------------------------------- scoreboard
class uart_scb_cfg extends uvm_object;
  `uvm_object_utils(uart_scb_cfg)

  // chequeos activos; +UART_SCB_EN=tx,rx,lsr (o all)
  bit chk_tx = 1, chk_rx = 1, chk_lsr = 1, chk_iir = 1, chk_msr = 1, chk_int = 1;
  int unsigned max_errors = 10;   // 0 = nunca detener
  // severidad de las diferencias conocidas del DUT (AMB-03, AMB-04)
  uvm_severity dut_bug_sev = UVM_WARNING;

  // el formato vigente, igual que en el agente serie
  uart_line_cfg line;
  uart_ctrl_cfg ctrl;

  function new(string name = "uart_scb_cfg");
    super.new(name);
  endfunction
endclass : uart_scb_cfg

// ---------------------------------------------------------------- cobertura
class uart_cov_cfg extends uvm_object;
  `uvm_object_utils(uart_cov_cfg)

  bit          enable      = 1;
  int unsigned curve_every = 1;   // [COV_CURVE] cada N episodios, 0 = no
  uart_line_cfg line;
  uart_ctrl_cfg ctrl;
  // modo del software en el episodio actual; lo pone la secuencia principal
  uart_sw_mode_e sw_mode = SW_IRQ;
  // para saber si un reset cayó en medio de un acceso al bus
  virtual wb_if  wb_vif;

  function new(string name = "uart_cov_cfg");
    super.new(name);
  endfunction
endclass : uart_cov_cfg
