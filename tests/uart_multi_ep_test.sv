//////////////////////////////////////////////////////////////////////////////
// uart_multi_ep_test:
// Pruebas con varios episodios por semilla
//////////////////////////////////////////////////////////////////////////////

class uart_multi_ep_test extends uart_base_test;
  `uvm_component_utils(uart_multi_ep_test)

  function new(string name = "uart_multi_ep_test", uvm_component parent = null); // constructor
    super.new(name, parent);
  endfunction

  virtual function void test_cfg();
    cfg.n_episodes = 4;   // máximo del plan; el reset y la reprogramación pasan entre episodios
  endfunction
endclass : uart_multi_ep_test
