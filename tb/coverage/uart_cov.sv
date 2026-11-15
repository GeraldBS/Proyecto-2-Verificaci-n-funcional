//////////////////////////////////////////////////////////////////////
// uart_cov: cobertura funcional (sección 13 del plan)              //
//////////////////////////////////////////////////////////////////////
// Recibe lo que ven los monitores y los eventos del modelo, nunca lo
// que mandan los drivers. Lleva una copia de DLAB e IER según las
// escrituras que pasaron por el bus, porque el ruido de registros
// puede cambiar IER sin pasar por uart_ctrl_cfg.
// Algunos covergroups se muestrean desde dos lugares; para eso tienen
// sample() con un argumento "kind" y cada coverpoint se filtra con iff.
//////////////////////////////////////////////////////////////////////
`uvm_analysis_imp_decl(_wb)
`uvm_analysis_imp_decl(_tx)
`uvm_analysis_imp_decl(_rx)
`uvm_analysis_imp_decl(_mdm)
`uvm_analysis_imp_decl(_int)
`uvm_analysis_imp_decl(_evt)

typedef enum {CK_CHAR, CK_PUSH, CK_RDEMPTY, CK_BREAK, CK_LEVEL, CK_EDGE, CK_IIR, CK_CHG, CK_MSR, CK_MCR} uart_cov_kind_e;

class uart_cov extends uvm_component;
  `uvm_component_utils(uart_cov)

  uvm_analysis_imp_wb  #(wb_item,        uart_cov) wb_imp;
  uvm_analysis_imp_tx  #(ser_item,       uart_cov) tx_imp;
  uvm_analysis_imp_rx  #(ser_item,       uart_cov) rx_imp;
  uvm_analysis_imp_mdm #(mdm_item,       uart_cov) mdm_imp;
  uvm_analysis_imp_int #(uart_int_item,  uart_cov) int_imp;
  uvm_analysis_imp_evt #(uart_model_evt, uart_cov) evt_imp;

  uart_cov_cfg cfg;

  // copias de lo que se escribió por el bus
  bit       dlab;
  bit [3:0] ier;
  bit       dll_written, dlm_written;   // qué byte del divisor se escribió en esta ventana de DLAB
  bit [7:0] dll_val, dlm_val;
  bit       tx_busy, rx_busy;  // del último evento del modelo
  int unsigned pending;
  bit       last_ri_rise;      // sentido del último cambio de RI (para TERI)
  int unsigned n_ep;

  // ------------------------------------------------------------ grupos
  covergroup cg_line_cfg with function sample(uart_ser_dir_e dir, bit [7:0] data);
    cp_dir : coverpoint dir;
    cp_wls : coverpoint cfg.line.wls { bins b5 = {0}; bins b6 = {1}; bins b7 = {2}; bins b8 = {3}; }
    cp_stb : coverpoint cfg.line.stb { bins uno = {0}; bins dos = {1}; }
    cp_par : coverpoint cfg.line.par_mode;
    cp_loop: coverpoint cfg.ctrl.loop;
    cp_dl_band : coverpoint cfg.line.dl {
      bins uno   = {1};
      bins rapido = {[2:16]};
      bins b17   = {[17:255]};
      bins b256  = {[256:4095]};
      bins b4096 = {[4096:65535]};
    }
    cp_data : coverpoint data { bins x00 = {8'h00}; bins xff = {8'hFF}; bins x55 = {8'h55};
                                bins xaa = {8'hAA}; bins otro = default; }
    cx_fmt   : cross cp_wls, cp_stb, cp_par, cp_dir;
    cx_loop  : cross cp_dir, cp_loop;
    cx_dl    : cross cp_dl_band, cp_dir;
  endgroup

  covergroup cg_dl with function sample(bit [15:0] dl, bit lsb_first);
    cp_dl : coverpoint dl {
      bins cero = {0}; bins uno = {1}; bins rapido = {[2:16]}; bins b17 = {[17:255]};
      bins b256 = {[256:4095]}; bins b4096 = {[4096:65534]}; bins maximo = {65535};
    }
    cp_order : coverpoint lsb_first { bins msb_primero = {0}; bins lsb_primero = {1}; }
    cx_dl_order : cross cp_dl, cp_order;
  endgroup

  covergroup cg_fifo_ctrl with function sample(bit [7:0] fcr, bit [1:0] traffic);
    cp_tl     : coverpoint fcr[7:6] { bins tl1 = {0}; bins tl4 = {1}; bins tl8 = {2}; bins tl14 = {3}; }
    cp_rx_clr : coverpoint fcr[1];
    cp_tx_clr : coverpoint fcr[2];
    cp_traffic: coverpoint traffic { bins reposo = {0}; bins tx = {1}; bins rx = {2}; bins ambos = {3}; }
    cx_clr    : cross cp_tl, cp_rx_clr, cp_tx_clr;
    cx_clr_tr : cross cp_rx_clr, cp_tx_clr, cp_traffic;
  endgroup

  covergroup cg_tx with function sample(uart_cov_kind_e kind, int unsigned level, bit lost);
    cp_level : coverpoint (lost ? 16 : level) iff (kind == CK_LEVEL) {
      bins vacia = {0}; bins uno = {1}; bins poca = {[2:7]}; bins media = {[8:14]};
      bins quince = {15}; bins perdida = {16};
    }
    cp_wls   : coverpoint cfg.line.wls iff (kind == CK_LEVEL);
    cx_level : cross cp_level, cp_wls;
    cp_break : coverpoint kind { bins brk = {CK_BREAK}; }
  endgroup

  covergroup cg_rx with function sample(uart_cov_kind_e kind, uart_ser_err_e err, bit [7:0] data,
                                        bit short_stop, int unsigned level, bit lost);
    cp_err : coverpoint err iff (kind == CK_CHAR) {
      bins ok = {SER_OK}; bins paridad = {SER_PARITY}; bins trama = {SER_FRAME};
      bins brk = {SER_BREAK}; bins glitch_desc = {SER_GLITCH}; bins glitch_inicio = {SER_GLITCH_START};
      bins baud_in = {SER_BAUD_IN}; bins baud_out = {SER_BAUD_OUT};
    }
    cp_par : coverpoint cfg.line.par_mode iff (kind == CK_CHAR);
    cp_wls : coverpoint cfg.line.wls iff (kind == CK_CHAR);
    cp_data: coverpoint data iff (kind == CK_CHAR) { bins x00 = {8'h00}; bins xff = {8'hFF}; bins otro = default; }
    cp_short_stop : coverpoint short_stop iff (kind == CK_CHAR && cfg.line.stb) { bins solo_uno = {1}; }
    cx_err_par : cross cp_err, cp_par {
      // sin paridad no hay bit que corromper
      ignore_bins sin_paridad = binsof(cp_err.paridad) && binsof(cp_par) intersect {PAR_NONE};
    }
    cx_err_wls : cross cp_err, cp_wls;
    // nivel de la FIFO RX al recibir, respecto al nivel de disparo
    cp_level : coverpoint level_cat(level, lost) iff (kind == CK_PUSH) {
      bins vacia = {0}; bins bajo_tl = {1}; bins en_tl = {2}; bins quince = {3}; bins overrun = {4};
    }
    cp_tl : coverpoint cfg.ctrl.tl iff (kind == CK_PUSH) { bins tl1 = {0}; bins tl4 = {1}; bins tl8 = {2}; bins tl14 = {3}; }
    cx_level_tl : cross cp_level, cp_tl {
      // con TL = 1 no existe "bajo el nivel de disparo" con datos
      ignore_bins tl1_bajo = binsof(cp_level.bajo_tl) && binsof(cp_tl.tl1);
    }
    cp_rd_empty : coverpoint kind { bins vacia = {CK_RDEMPTY}; }
  endgroup

  covergroup cg_err with function sample(bit [7:0] lsr);
    cp_dr  : coverpoint lsr[0];
    cp_oe  : coverpoint lsr[1];
    cp_pe  : coverpoint lsr[2];
    cp_fe  : coverpoint lsr[3];
    cp_bi  : coverpoint lsr[4];
    cp_thre: coverpoint lsr[5];
    cp_temt: coverpoint lsr[6];
    cp_fifo_err : coverpoint lsr[7];
    cp_tl  : coverpoint cfg.ctrl.tl { bins tl1 = {0}; bins tl4 = {1}; bins tl8 = {2}; bins tl14 = {3}; }
    cp_wls : coverpoint cfg.line.wls;
    cx_oe_tl : cross cp_oe, cp_tl;
    cx_pe_wls: cross cp_pe, cp_wls;
    cx_fe_wls: cross cp_fe, cp_wls;
    cx_bi_wls: cross cp_bi, cp_wls;
    cx_tx    : cross cp_thre, cp_temt {
      // el transmisor no puede estar vacío con datos en la FIFO; si sale, es un error del DUT
      illegal_bins temt_sin_thre = binsof(cp_thre) intersect {0} && binsof(cp_temt) intersect {1};
    }
  endgroup

  covergroup cg_int with function sample(uart_cov_kind_e kind, bit [7:0] iir, bit level);
    cp_iir_id : coverpoint iir[3:0] iff (kind == CK_IIR) {
      bins ninguna = {4'b0001}; bins rls = {4'b0110}; bins rda = {4'b0100};
      bins timeout = {4'b1100}; bins thre = {4'b0010}; bins msi = {4'b0000};
    }
    cp_ier  : coverpoint ier iff (kind == CK_IIR);
    cp_mode : coverpoint cfg.sw_mode iff (kind == CK_IIR);
    cp_multi: coverpoint pending iff (kind == CK_IIR) { bins cero = {0}; bins una = {1}; bins dos = {2}; bins mas = {[3:$]}; }
    cp_tl   : coverpoint cfg.ctrl.tl iff (kind == CK_IIR);
    cx_id_mode  : cross cp_iir_id, cp_mode;
    cx_id_multi : cross cp_iir_id, cp_multi {
      ignore_bins ninguna_pend = binsof(cp_iir_id.ninguna) && binsof(cp_multi) intersect {[1:$]};
      ignore_bins id_sin_pend  = !binsof(cp_iir_id.ninguna) && binsof(cp_multi.cero);
    }
    cx_id_tl    : cross cp_iir_id, cp_tl;
    // una interrupción con su bit de IER en 0 está enmascarada y no puede aparecer
    cx_id_ier   : cross cp_iir_id, cp_ier {
      ignore_bins rls_off  = binsof(cp_iir_id.rls)     && binsof(cp_ier) intersect {0,1,2,3,8,9,10,11};
      ignore_bins rda_off  = binsof(cp_iir_id.rda)     && binsof(cp_ier) intersect {0,2,4,6,8,10,12,14};
      ignore_bins to_off   = binsof(cp_iir_id.timeout) && binsof(cp_ier) intersect {0,2,4,6,8,10,12,14};
      ignore_bins thre_off = binsof(cp_iir_id.thre)    && binsof(cp_ier) intersect {0,1,4,5,8,9,12,13};
      ignore_bins msi_off  = binsof(cp_iir_id.msi)     && binsof(cp_ier) intersect {[0:7]};
    }
    cp_int_edge : coverpoint level iff (kind == CK_EDGE) { bins sube = {1}; bins baja = {0}; }
  endgroup

  covergroup cg_modem with function sample(uart_cov_kind_e kind, int unsigned sig, bit rise, bit [7:0] val);
    cp_sig  : coverpoint sig iff (kind == CK_CHG) { bins cts = {0}; bins dsr = {1}; bins ri = {2}; bins dcd = {3}; }
    cp_edge : coverpoint rise iff (kind == CK_CHG) { bins sube = {1}; bins baja = {0}; }
    cp_loop : coverpoint cfg.ctrl.loop iff (kind == CK_CHG);
    cx_sig  : cross cp_sig, cp_edge, cp_loop;
    cp_delta : coverpoint val[3:0] iff (kind == CK_MSR) {
      wildcard bins dcts = {4'b???1}; wildcard bins ddsr = {4'b??1?};
      wildcard bins teri = {4'b?1??}; wildcard bins ddcd = {4'b1???};
    }
    cp_teri : coverpoint last_ri_rise iff (kind == CK_MSR && val[2]) { bins con_ri_sube = {1}; bins con_ri_baja = {0}; }
    cp_out  : coverpoint val[3:0] iff (kind == CK_MCR);
    cp_out_loop : coverpoint val[4] iff (kind == CK_MCR);
    cx_out  : cross cp_out, cp_out_loop;
  endgroup

  covergroup cg_reg_access with function sample(bit [4:0] adr, bit we, bit dl, bit [3:0] sel);
    cp_addr : coverpoint adr { bins regs[] = {[0:7]}; bins dbg1 = {8}; bins dbg2 = {12}; }
    cp_rw   : coverpoint we { bins lee = {0}; bins escribe = {1}; }
    cp_dlab : coverpoint dl;
    cp_sel  : coverpoint sel {
      bins carril[] = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
      bins todos = {4'b1111}; bins ninguno = {4'b0000};
      bins varios = {4'b0011, 4'b0101, 4'b0110, 4'b1001, 4'b1010, 4'b1100, 4'b0111, 4'b1011, 4'b1101, 4'b1110};
    }
    cx_addr_rw_dlab : cross cp_addr, cp_rw, cp_dlab {
      // con DLAB = 1 no se escribe FCR ni MCR: la reconfiguración se hace con DLAB = 0
      ignore_bins fcr_mcr_dlab = binsof(cp_rw.escribe) && binsof(cp_dlab) intersect {1} &&
                                 binsof(cp_addr) intersect {2, 4};
    }
    cx_sel_rw : cross cp_sel, cp_rw;
  endgroup

  covergroup cg_reset with function sample(bit [2:0] when, int unsigned width);
    cp_when  : coverpoint when { bins reposo = {0}; bins tx = {1}; bins rx = {2}; bins ambos = {3}; bins en_acceso = {4}; }
    cp_width : coverpoint width { bins uno = {1}; bins varios = {[2:$]}; }
    cx_reset : cross cp_when, cp_width;
  endgroup

  covergroup cg_reconfig with function sample(bit [2:0] reg_k, bit [1:0] traffic);
    cp_reg     : coverpoint reg_k { bins lcr = {0}; bins dl = {1}; bins fcr = {2}; bins mcr = {3}; }
    cp_traffic : coverpoint traffic { bins tx = {1}; bins rx = {2}; bins ambos = {3}; }
    cx_reconfig: cross cp_reg, cp_traffic;
  endgroup

  // ------------------------------------------------------------ armado
  function new(string name, uvm_component parent);
    super.new(name, parent);
    wb_imp  = new("wb_imp",  this);
    tx_imp  = new("tx_imp",  this);
    rx_imp  = new("rx_imp",  this);
    mdm_imp = new("mdm_imp", this);
    int_imp = new("int_imp", this);
    evt_imp = new("evt_imp", this);
    // los covergroups de una clase solo se pueden construir en new()
    cg_line_cfg   = new();
    cg_dl         = new();
    cg_fifo_ctrl  = new();
    cg_tx         = new();
    cg_rx         = new();
    cg_err        = new();
    cg_int        = new();
    cg_modem      = new();
    cg_reg_access = new();
    cg_reset      = new();
    cg_reconfig   = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(uart_cov_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "No se encontró la configuración de cobertura")
    // con +UART_COV_EN=0 los write_* salen sin muestrear nada
  endfunction

  // [COV_CURVE] al final de cada episodio, para la curva de la línea base
  task run_phase(uvm_phase phase);
    uvm_event ep_end = uvm_event_pool::get_global("uart_ep_end");
    if (!cfg.enable || cfg.curve_every == 0) return;
    forever begin
      ep_end.wait_trigger();
      n_ep++;
      if (n_ep % cfg.curve_every == 0)
        `uvm_info("COV_CURVE", $sformatf("ep=%0d fcov=%0.2f", n_ep, total()), UVM_NONE)
    end
  endtask

  function real total();
    real s = cg_line_cfg.get_coverage() + cg_dl.get_coverage() + cg_fifo_ctrl.get_coverage() +
             cg_tx.get_coverage() + cg_rx.get_coverage() + cg_err.get_coverage() +
             cg_int.get_coverage() + cg_modem.get_coverage() + cg_reg_access.get_coverage() +
             cg_reset.get_coverage() + cg_reconfig.get_coverage();
    return s / 11.0;
  endfunction

  function void report_phase(uvm_phase phase);
    if (cfg.enable)
      `uvm_info("COV", $sformatf("cobertura funcional total: %0.2f %%", total()), UVM_NONE)
  endfunction

  // nivel de la FIFO RX en categorías respecto al nivel de disparo
  function int unsigned level_cat(int unsigned level, bit lost);
    if (lost)                                  return 4;
    if (level >= 15)                           return 3;
    if (level >= cfg.ctrl.trigger_level())     return 2;
    if (level > 0)                             return 1;
    return 0;
  endfunction

  function bit [1:0] traffic(); return {rx_busy, tx_busy}; endfunction

  // ------------------------------------------------------------ entradas
  // El monitor publica el bus tal cual: dat y dat_rd en su carril y el
  // sel que de verdad salió. Con uart_reg_of y uart_lane8 vemos el
  // registro y el byte que usó el DUT, aunque el sel sea inválido.
  function void write_wb(wb_item item);
    bit [4:0] reg_idx;
    bit [7:0] wr_byte, rd_byte;
    if (!cfg.enable) return;
    reg_idx = uart_reg_of(item.adr, item.sel);
    wr_byte = uart_lane8(item.sel, item.dat);
    rd_byte = uart_lane8(item.sel, item.dat_rd);
    // cp_addr es la dirección que pidió la secuencia y cp_sel el sel real
    cg_reg_access.sample(item.adr, item.we, dlab, item.sel);
    if (item.we) begin
      case (reg_idx)
        UART_LCR: begin
          if (wr_byte[7] && !dlab) begin dll_written = 0; dlm_written = 0; end   // abre ventana de DLAB
          dlab = wr_byte[7];
          if (traffic() != 0) cg_reconfig.sample(0, traffic());
        end
        UART_IER: if (!dlab) ier = wr_byte[3:0];
        UART_FCR: begin
          cg_fifo_ctrl.sample(wr_byte, traffic());
          if (traffic() != 0) cg_reconfig.sample(2, traffic());
        end
        UART_MCR: begin
          cg_modem.sample(CK_MCR, 0, 0, wr_byte);
          if (traffic() != 0) cg_reconfig.sample(3, traffic());
        end
        default: ;
      endcase
      // divisor: se cuenta cuando ya se escribieron los dos bytes
      if (dlab && reg_idx == UART_DLL) begin
        dll_val = wr_byte;
        if (dlm_written) cg_dl.sample({dlm_val, dll_val}, 1'b0);
        dll_written = 1;
        if (traffic() != 0) cg_reconfig.sample(1, traffic());
      end
      if (dlab && reg_idx == UART_DLM) begin
        dlm_val = wr_byte;
        if (dll_written) cg_dl.sample({dlm_val, dll_val}, 1'b1);
        dlm_written = 1;
      end
    end else if (!dlab && item.sel_kind() == SEL_ONE) begin
      // con sel inválido el DUT devuelve 0 o la palabra de Debug, así que
      // esas lecturas no dicen nada de LSR, IIR ni MSR
      case (reg_idx)
        UART_LSR: cg_err.sample(rd_byte);
        UART_IIR: cg_int.sample(CK_IIR, rd_byte, 0);
        UART_MSR: cg_modem.sample(CK_MSR, 0, 0, rd_byte);
        default: ;
      endcase
    end
  endfunction

  function void write_tx(ser_item item);
    if (!cfg.enable) return;
    if (item.err == SER_BREAK) cg_tx.sample(CK_BREAK, 0, 0);
    else                       cg_line_cfg.sample(SER_DIR_TX, item.data);
  endfunction

  function void write_rx(ser_item item);
    if (!cfg.enable) return;
    cg_rx.sample(CK_CHAR, item.err, item.data, item.short_stop, 0, 0);
    if (item.err inside {SER_OK, SER_BAUD_IN}) cg_line_cfg.sample(SER_DIR_RX, item.data);
  endfunction

  function void write_mdm(mdm_item item);
    if (!cfg.enable) return;
    for (int i = 0; i < 4; i++) begin
      if (item.in_chg[i]) begin
        cg_modem.sample(CK_CHG, i, item.in_val[i], 0);
        if (i == 2) last_ri_rise = item.in_val[2];
      end
    end
  endfunction

  function void write_int(uart_int_item item);
    if (!cfg.enable) return;
    cg_int.sample(CK_EDGE, 0, item.level);
  endfunction

  function void write_evt(uart_model_evt item);
    if (!cfg.enable) return;
    tx_busy = item.tx_busy;
    rx_busy = item.rx_busy;
    pending = item.pending_cnt;
    case (item.kind)
      EV_THR_WRITE: cg_tx.sample(CK_LEVEL, item.tx_level, item.lost);
      EV_RX_PUSH:   cg_rx.sample(CK_PUSH, SER_OK, 0, 0, item.rx_level, item.lost);
      EV_RBR_READ:  if (item.rx_level == 0) cg_rx.sample(CK_RDEMPTY, SER_OK, 0, 0, 0, 0);
      EV_RESET: begin
        bit [2:0] when = (cfg.wb_vif != null && cfg.wb_vif.cyc === 1'b1) ? 3'd4 : {1'b0, item.rx_busy, item.tx_busy};
        cg_reset.sample(when, item.rst_cycles);
        dlab = 0;
        ier  = 0;
      end
      default: ;
    endcase
  endfunction
endclass : uart_cov
