// Wishbone
class wb_agent_cfg extends uvm_object;
  `uvm_object_utils(wb_agent_cfg)
  virtual wb_if          vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  // constantes del driver para separar y retrasar transacciones
  int unsigned gap_max       = 4;
  int unsigned gap_zero_pct  = 60;
  int unsigned stb_delay_pct = 20;
  int unsigned stb_delay_max = 3;
  // en 0 en la base, solo CE-16 lo sube (AMB-05)
  int unsigned bad_sel_pct   = 0;

  function new(string name = "wb_agent_cfg");
    super.new(name);
  endfunction
endclass : wb_agent_cfg

// serie
class uart_ser_agent_cfg extends uvm_object;
  `uvm_object_utils(uart_ser_agent_cfg)
  virtual uart_ser_if    vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  bit           loopback; // en loopback el DUT ignora srx, el driver lo deja en reposo

  // knobs de recepcion
  int unsigned rx_gap_mode     = 0;           // 0 mezcla, 1 sin pausa, 2 solo pausas largas
  int unsigned parity_err_pct  = 5;
  int unsigned break_pct       = 3;
  int unsigned glitch_pct      = 3;
  int unsigned baud_in_pct     = 10;
  int unsigned baud_out_pct    = 2;
  int unsigned short_stop_pct  = 5;

  // constantes, ya no tienen plusarg en el plan nuevo
  int unsigned rx_chars_max    = 40;
  int unsigned slow_dl         = 256;         // desde aqui se limita el trafico
  int unsigned slow_chars_max  = 2;
  int unsigned rx_gap_max      = 80;          // bits
  int unsigned rx_gap_w[]      = '{60, 30, 10};  // 0, 1-15 bits, 16-max bits
  int unsigned frame_err_pct   = 5;
  int unsigned break_extra_max = 2;           // Tc
  int unsigned glitch_w_max    = 15;          // dieciseisavos de bit
  int unsigned baud_in_max     = 25;          // décimas de %
  int unsigned baud_out_min    = 50;
  int unsigned baud_out_max    = 100;

  function new(string name = "uart_ser_agent_cfg");
    super.new(name);
  endfunction
endclass : uart_ser_agent_cfg

// Módem
class modem_agent_cfg extends uvm_object;
  `uvm_object_utils(modem_agent_cfg)
  virtual modem_if       vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  int unsigned changes_max = 8;
  // constantes
  int unsigned sig_w[]     = '{1, 1, 1, 1};   // CTS, DSR, RI, DCD
  int unsigned gap_max     = 4;               // Tc
  int unsigned multi_pct   = 10;

  function new(string name = "modem_agent_cfg");
    super.new(name);
  endfunction
endclass : modem_agent_cfg

// scoreboard
class uart_scb_cfg extends uvm_object;
  `uvm_object_utils(uart_scb_cfg)

  // todos los chequeos van siempre, ya no hay +UART_SCB_EN
  bit chk_tx = 1, chk_rx = 1, chk_lsr = 1, chk_iir = 1, chk_msr = 1, chk_int = 1;
  int unsigned max_errors = 10;   // 0 = nunca detener
  // severidad de las diferencias conocidas del DUT
  uvm_severity dut_bug_sev = UVM_WARNING;

  uart_line_cfg line;
  uart_ctrl_cfg ctrl;

  function new(string name = "uart_scb_cfg"); // constructor
    super.new(name);
  endfunction
endclass : uart_scb_cfg

// cobertura
class uart_cov_cfg extends uvm_object;
  `uvm_object_utils(uart_cov_cfg)

  bit          enable      = 1;
  int unsigned curve_every = 1;   // una linea [COV_CURVE] por episodio
  uart_line_cfg line;
  uart_ctrl_cfg ctrl;

  uart_sw_mode_e sw_mode = SW_IRQ;
  virtual wb_if  wb_vif;

  function new(string name = "uart_cov_cfg");
    super.new(name);
  endfunction
endclass : uart_cov_cfg
