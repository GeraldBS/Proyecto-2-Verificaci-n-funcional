// CE-14 y CE-20, ver que deja una configuracion (o un reset) en la siguiente
class uart_multi_ep_test extends uart_base_test;
  `uvm_component_utils(uart_multi_ep_test)

  function new(string name = "uart_multi_ep_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void test_cfg();
    cfg.n_episodes = 4;   // maximo del plan
  endfunction
endclass : uart_multi_ep_test
