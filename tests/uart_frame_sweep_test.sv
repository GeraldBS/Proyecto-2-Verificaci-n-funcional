// CE-05, con las semillas 1 a 20 pasa dos veces por los 40 formatos
class uart_frame_sweep_test extends uart_base_test;
  `uvm_component_utils(uart_frame_sweep_test)

  function new(string name = "uart_frame_sweep_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void test_cfg();
    cfg.n_episodes  = 4;
    cfg.frame_sweep = 1;
  endfunction
endclass : uart_frame_sweep_test
