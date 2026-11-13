//////////////////////////////////////////////////////////////////////////////////
// wb_monitor.sv
// observa el bus sin manejar señales y publica
//////////////////////////////////////////////////////////////////////////////////

class wb_monitor extends uvm_monitor;
  `uvm_component_utils(wb_monitor)   // macro de UVM: registra la clase en la factory

  wb_agent_cfg cfg;   // knobs del agente 
  virtual wb_if vif;   // interfaz virtual del bus Wishbone

  uvm_analysis_port #(wb_item)     ap;   // un wb_item por acceso terminado
  uvm_analysis_port #(wb_rst_item) rst_ap;   // eventos de reset (sube y baja)

  // Constructor
  function new(string name = "wb_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // Obtiene wb_agent_cfg y crea los puertos de análisis
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(wb_agent_cfg)::get(this, "", UART_KEY_CFG, cfg))   // busca la configuración publicada por el test
      `uvm_fatal("NOCFG", "wb_monitor: wb_agent_cfg no se encontró en uvm_config_db")   // error
    vif = cfg.vif;
    if (vif == null)
      `uvm_fatal("NOVIF", "wb_monitor: wb_agent_cfg.vif no está asignada")   // error
    ap     = new("ap", this);   // crea el puerto de análisis
    rst_ap = new("rst_ap", this);   // crea el puerto de análisis
  endfunction

  // Lanza en paralelo la observación de accesos y de resets
  task run_phase(uvm_phase phase);
    fork
      collect_transfers();
      collect_resets();
    join
  endtask

  task collect_transfers();
    wb_item item;   // acceso que se publica
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.rst === 1'b1) continue;
      if (vif.mon_cb.cyc === 1'b1 && vif.mon_cb.stb === 1'b1 && vif.mon_cb.ack === 1'b1) begin
        item = wb_item::type_id::create("wb_mon_item");   // crea el objeto con la factory
        item.adr    = vif.mon_cb.adr;
        item.sel    = vif.mon_cb.sel;
        item.we     = vif.mon_cb.we;
        item.dat    = vif.mon_cb.dat_m2s;
        item.dat_rd = vif.mon_cb.dat_s2m;
        item.t_end  = $realtime;
        `uvm_info("WB_MON", item.convert2string(), UVM_HIGH)   // imprime solo con UVM_HIGH
        ap.write(item);
      end
    end
  endtask

  // Detecta cuándo sube y baja el reset y mide su ancho en ciclos de reloj.
  task collect_resets();
    wb_rst_item  ev;   // evento de reset que se publica
    bit          prev   = 0;   // el reset estaba activo en el ciclo anterior
    bit          first  = 1;   // 1 hasta ver el primer reset (el de arranque)
    bit          during = 0;   // había un acceso en curso cuando subió el reset
    bit          init   = 0;   // este reset es el inicial
    int unsigned cnt    = 0;   // ciclos de reloj con el reset activo
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.rst === 1'b1) begin
        if (!prev) begin
          cnt    = 0;
          during = (vif.mon_cb.cyc === 1'b1 && vif.mon_cb.stb === 1'b1);
          init   = first;
          first  = 0;
          ev = wb_rst_item::type_id::create("wb_rst_start");   // crea el objeto con la factory
          ev.asserted      = 1;
          ev.during_access = during;
          ev.is_initial    = init;
          ev.t             = $realtime;
          `uvm_info("WB_MON", ev.convert2string(), UVM_HIGH)   // macro de UVM: imprime solo con UVM_HIGH
          rst_ap.write(ev);
        end
        cnt++;
        prev = 1;
      end
      else if (prev) begin
        ev = wb_rst_item::type_id::create("wb_rst_end");   // crea el objeto con la factory
        ev.asserted      = 0;
        ev.width_cycles  = cnt;
        ev.during_access = during;
        ev.is_initial    = init;
        ev.t             = $realtime;
        `uvm_info("WB_MON", ev.convert2string(), UVM_HIGH)   // macro de UVM: imprime solo con UVM_HIGH
        rst_ap.write(ev);
        prev = 0;
      end
    end
  endtask
endclass : wb_monitor
