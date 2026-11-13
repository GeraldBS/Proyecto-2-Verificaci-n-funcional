//////////////////////////////////////////////////////////////////////////////////
// wb_driver.sv
// 
//////////////////////////////////////////////////////////////////////////////////

class wb_driver extends uvm_driver #(wb_item);
  `uvm_component_utils(wb_driver)   // macro de UVM: registra la clase en la factory

  wb_agent_cfg cfg;   // knobs del agente (pausas, retraso de stb, sel inválido)
  virtual wb_if vif;   // interfaz virtual del bus Wishbone

  real t_clk = 20.0;                  // periodo del reloj en ns (se mide al inicio)
  localparam int ACK_TIMEOUT = 16;    // ciclos máximos de espera del ack

  // Constructor
  function new(string name = "wb_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // Obtiene wb_agent_cfg y la interfaz virtual
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(wb_agent_cfg)::get(this, "", UART_KEY_CFG, cfg))   // busca la configuración publicada por el test
      `uvm_fatal("NOCFG", "wb_driver: no se encontró wb_agent_cfg en uvm_config_db")   // macro de UVM: error fatal si no hay configuración
    vif = cfg.vif;
    if (vif == null)
      `uvm_fatal("NOVIF", "wb_driver: wb_agent_cfg.vif no está asignada")   // macro de UVM: error fatal si no hay interfaz
  endfunction

  // Mide el periodo del reloj y atiende los items del secuenciador
  task run_phase(uvm_phase phase);
    realtime t0;   // instante del primer flanco de reloj
    // Mide el periodo del reloj para poder dar anchos de reset en ciclos
    @(posedge vif.clk);
    t0 = $realtime;
    @(posedge vif.clk);
    t_clk = $realtime - t0;

  endtask

  task drive(wb_item it);
    int unsigned gap, sd, waited;   // pausa previa, retraso de stb y ciclos esperando el ack
    bit          rst_seen;   // 1 si un reset estuvo activo durante el acceso

    gap = it.gap_is_auto()       ? pick_gap()       : it.gap;
    sd  = it.stb_delay_is_auto() ? pick_stb_delay() : it.stb_delay;

    wait_cycles(gap, rst_seen);
    wait_reset_end();

    // sel inválido (AMB-05) solo si el item lo permite
    it.sel = pick_sel(it);

    it.t_start = $realtime;
    vif.drv_cb.adr     <= it.adr;
    vif.drv_cb.dat_m2s <= it.dat;
    vif.drv_cb.sel     <= it.sel;
    vif.drv_cb.we      <= it.we;
    vif.drv_cb.cyc     <= 1'b1;

    
    it.aborted = rst_seen;
    it.t_end   = $realtime;

    // Fin de la transferencia: cyc y stb bajan y se deja un ciclo en reposo
    vif.drv_cb.cyc <= 1'b0;
    vif.drv_cb.stb <= 1'b0;
    @(vif.drv_cb);
  endtask

  // Decisiones aleatorias 
  function int unsigned pick_gap();
    if (cfg.wb_gap_max < 1) return 0;
    if ($urandom_range(99) < cfg.wb_gap_zero_pct) return 0;
    return $urandom_range(cfg.wb_gap_max, 1);
  endfunction

  // 80 % sin retraso, 20 % de 1 a wb_stb_delay_max ciclos
  function int unsigned pick_stb_delay();
    if (cfg.wb_stb_delay_max < 1) return 0;
    if ($urandom_range(99) >= cfg.wb_stb_delay_pct) return 0;
    return $urandom_range(cfg.wb_stb_delay_max, 1);
  endfunction

  // Con probabilidad wb_bad_sel_pct cambia sel de un registro de 8 bits (adr < 8)
  // por 0000, dos bits o 1111 (AMB-05). Si no, deja el sel del item.
  function bit [3:0] pick_sel(wb_item it);
    bit [3:0] two_bits[6] = '{4'b0011, 4'b0101, 4'b0110, 4'b1001, 4'b1010, 4'b1100};   // combinaciones con dos bits activos
    if (!it.bad_sel_ok || it.adr[4:2] > 3'd1) return it.sel;
    if ($urandom_range(99) >= cfg.wb_bad_sel_pct) return it.sel;
    it.sel_injected = 1;
    case ($urandom_range(2))
      0:       return 4'b0000;
      1:       return two_bits[$urandom_range(5)];
      default: return 4'b1111;
    endcase
  endfunction
endclass : wb_driver
