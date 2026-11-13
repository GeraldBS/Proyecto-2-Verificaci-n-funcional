//////////////////////////////////////////////////////////////////////////////////
// uart_int_monitor.sv
// Vigila int_o (wb_if.irq) y publica un uart_int_item en cada flanco, para el
// scoreboard (modelo de interrupciones) y la cobertura (cg_int.cp_int_edge).
// int_o cambia solo con el reloj (o con el reset asíncrono), in_reset indica
// si el flanco ocurrió con el reset activo.
//////////////////////////////////////////////////////////////////////////////////

class uart_int_monitor extends uvm_monitor;
  `uvm_component_utils(uart_int_monitor)   // macro de UVM: registra la clase en la factory

  wb_agent_cfg cfg;   // knobs del agente (de ahí sale la interfaz virtual)
  virtual wb_if vif;   // interfaz virtual del bus Wishbone

  uvm_analysis_port #(uart_int_item) ap;   // un uart_int_item por flanco de int_o

  // Constructor
  function new(string name = "uart_int_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // Obtiene wb_agent_cfg y crea el puerto de análisis
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(wb_agent_cfg)::get(this, "", UART_KEY_CFG, cfg))   // busca la configuración publicada por el test
      `uvm_fatal("NOCFG", "uart_int_monitor: no se encontró wb_agent_cfg en uvm_config_db")   // macro de UVM: error fatal si no hay configuración
    vif = cfg.vif;
    if (vif == null)
      `uvm_fatal("NOVIF", "uart_int_monitor: wb_agent_cfg.vif no está asignada")   // macro de UVM: error fatal si no hay interfaz
    ap = new("ap", this);   // crea el puerto de análisis
  endfunction

  // Compara int_o en cada ciclo y publica los flancos
  task run_phase(uvm_phase phase);
    uart_int_item it;   // flanco que se publica
    bit prev;   // valor de int_o en el ciclo anterior
    bit have_prev = 0;   // 1 cuando ya hay un valor anterior válido
    bit cur;   // valor de int_o en este ciclo
    
    forever begin
      @(vif.mon_cb);
      if ($isunknown(vif.mon_cb.irq)) continue;   // antes del primer reset puede ser X
      cur = vif.mon_cb.irq;
      if (have_prev && cur != prev) begin
        it = uart_int_item::type_id::create("int_item");   // crea el objeto con la factory
        it.level    = cur;
        it.in_reset = (vif.mon_cb.rst === 1'b1);
        it.t        = $realtime;
        `uvm_info("INT_MON", it.convert2string(), UVM_HIGH)   // macro de UVM: imprime solo con UVM_HIGH
        ap.write(it);   // publica el flanco
      end
      prev      = cur;
      have_prev = 1;
    end
  endtask
endclass : uart_int_monitor
