//////////////////////////////////////////////////////////////////////////////////
// wb_driver.sv
// convierte cada wb_item en un acceso al bus.
//////////////////////////////////////////////////////////////////////////////////

class wb_driver extends uvm_driver #(wb_item);
  `uvm_component_utils(wb_driver)   // macro de UVM: registra la clase en la factory

  wb_agent_cfg cfg;   // knobs del agente 
  virtual wb_if vif;   // interfaz virtual del bus Wishbone

  real t_clk = 20.0;                  // periodo del reloj 
  localparam int ACK_TIMEOUT = 16;    // ciclos máximos de espera del ack

  // Constructor
  function new(string name = "wb_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // Obtiene wb_agent_cfg y la interfaz virtual
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(wb_agent_cfg)::get(this, "", UART_KEY_CFG, cfg))   // busca la configuración publicada por el test
      `uvm_fatal("NOCFG", "wb_agent_cfg no se encontró en uvm_config_db")   // error
    vif = cfg.vif;
    if (vif == null)
      `uvm_fatal("NOVIF", "wb_driver: wb_agent_cfg.vif no está asignada")   // error

  // Mide el periodo del reloj y atiende los items del secuenciador
  task run_phase(uvm_phase phase);
    realtime t0;   //primer flanco de reloj
    @(posedge vif.clk);
    t0 = $realtime;
    @(posedge vif.clk);
    t_clk = $realtime - t0;

    forever begin
      seq_item_port.get_next_item(req);   // pide el siguiente item al secuenciador
      drive(req);   // ejecuta el acceso en el bus
      seq_item_port.item_done();   // avisa al secuenciador que terminó
    end
  endtask

  task drive(wb_item item); // pausa previa, retraso de stb y ciclos esperando el ack
    int unsigned gap;   
    int unsigned sd;
    int unsigned waited;
    bit          rst_seen;   // 1 si un reset estuvo activo durante el acceso

    gap = item.gap_is_auto()       ? pick_gap()       : item.gap;
    sd  = item.stb_delay_is_auto() ? pick_stb_delay() : item.stb_delay;

    wait_cycles(gap, rst_seen);
    wait_reset_end();

    item.sel = pick_sel(item);

    // armar el pedido (de datos a señales)
    item.t_start = $realtime;
    vif.drv_cb.adr     <= item.adr;
    vif.drv_cb.dat_m2s <= item.dat;
    vif.drv_cb.sel     <= item.sel;
    vif.drv_cb.we      <= item.we;
    vif.drv_cb.cyc     <= 1'b1;


    wait_cycles(sd, rst_seen);
    if (!rst_seen) begin
      vif.drv_cb.stb <= 1'b1;
      // Espera el ack sin suponer latencia fija
      waited = 0;
      forever begin
        @(vif.drv_cb);
        if (vif.rst) begin rst_seen = 1; break; end
        if (vif.drv_cb.ack === 1'b1) begin
          item.dat_rd = vif.drv_cb.dat_s2m;
          break;
        end
        waited++;
        if (waited >= ACK_TIMEOUT) begin
          item.timeout = 1;
          `uvm_error("WB_TIMEOUT", $sformatf("sin ack en %0d ciclos: %s", ACK_TIMEOUT, item.convert2string()))   // macro de UVM: reporta el error y sigue
          break;
        end
      end
    end
    item.aborted = rst_seen;
    item.t_end   = $realtime;

    // Fin de la transferencia: cyc y stb bajan y se deja un ciclo en reposo
    vif.drv_cb.cyc <= 1'b0;
    vif.drv_cb.stb <= 1'b0;
    @(vif.drv_cb);
  endtask

  // Espera n ciclos de reloj; rst_seen = 1 si el reset estuvo activo en alguno.
  task wait_cycles(int unsigned n, output bit rst_seen);
    rst_seen = 0;
    repeat (n) begin
      @(vif.drv_cb);
      if (vif.rst) rst_seen = 1;
    end
  endtask

  task wait_reset_end();
    while (vif.rst) @(vif.drv_cb);
  endtask

  // reset
  task apply_async_reset(int unsigned width_cycles, real phase_ns);
    @(posedge vif.clk);
    #(phase_ns);
    vif.rst = 1'b1;
    #(width_cycles * t_clk);
    vif.rst = 1'b0;
  endtask

  function int unsigned pick_gap();
    if (cfg.gap_max < 1) return 0;
    if ($urandom_range(99) < cfg.gap_zero_pct) return 0;
    return $urandom_range(cfg.gap_max, 1);
  endfunction

  function int unsigned pick_stb_delay();
    if (cfg.stb_delay_max < 1) return 0;
    if ($urandom_range(99) >= cfg.stb_delay_pct) return 0;
    return $urandom_range(cfg.stb_delay_max, 1);
  endfunction

  function bit [3:0] pick_sel(wb_item item);
    bit [3:0] two_bits[6] = '{4'b0011, 4'b0101, 4'b0110, 4'b1001, 4'b1010, 4'b1100};   // combinaciones con dos bits activos
    if (!item.bad_sel_ok || item.adr[4:2] > 3'd1) return item.sel;
    if ($urandom_range(99) >= cfg.bad_sel_pct) return item.sel;
    item.sel_injected = 1;
    case ($urandom_range(2))
      0:       return 4'b0000;
      1:       return two_bits[$urandom_range(5)];
      default: return 4'b1111;
    endcase
  endfunction
endclass : wb_driver
