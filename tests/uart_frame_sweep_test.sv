//////////////////////////////////////////////////////////////////////////////
// uart_frame_sweep_test:
// Recorre los 40 formatos de trama con 4 episodios por semilla.
//////////////////////////////////////////////////////////////////////////////

class uart_frame_sweep_test extends uart_base_test;
  `uvm_component_utils(uart_frame_sweep_test)

  function new(string name = "uart_frame_sweep_test", uvm_component parent = null); // constructor
    super.new(name, parent);
  endfunction

  virtual function void test_cfg();
    int s;
    cfg.n_episodes = 4;    // máximo del plan; un formato por episodio
    cfg.frame_sweep = 1;   // uart_main_vseq fija el formato y manda TX, RX y errores en cada uno
    // la semilla elige el grupo de 4 formatos
    if ($value$plusargs("ntb_random_seed=%d", s)) cfg.seed = s;
  endfunction
endclass : uart_frame_sweep_test
