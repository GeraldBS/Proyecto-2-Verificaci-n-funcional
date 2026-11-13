//////////////////////////////////////////////////////////////////////
// uart_sw_vseq: el "software" que atiende al UART                  //
//////////////////////////////////////////////////////////////////////
// Corre todo el episodio, hasta que el tráfico termina. En modo de
// interrupciones espera int_o y lee IIR; en modo de sondeo lee LSR
// cada cierto tiempo. En los dos casos tarda sw_delay en atender (así
// salen el overrun y el timeout) y a veces hace un acceso de ruido a
// una dirección al azar.
//////////////////////////////////////////////////////////////////////
class uart_sw_vseq extends uart_base_vseq;
  `uvm_object_utils(uart_sw_vseq)

  uart_sw_mode_e mode;   // lo decide la secuencia principal

  function new(string name = "uart_sw_vseq");
    super.new(name);
  endfunction

  // retraso de atención en Tc: corto (0-1), medio (2-6) o largo (7-max)
  function int unsigned pick_delay();
    int unsigned band_lo[3] = '{0, 2, 7};
    int unsigned band_hi[3] = '{1, 6, 'hFFFF};
    return pick_band3(cfg().sw_delay_w, band_lo, band_hi, cfg().sw_delay_min, cfg().sw_delay_max);
  endfunction

  task body();
    while (!p_sequencer.traffic_done && !stop_now()) begin
      if (mode == SW_IRQ) begin
        // espera int_o, con un sondeo de respaldo cada 32 Tc por si
        // IER = 0 o se perdió el aviso
        fork : espera
          wait (p_sequencer.cfg.wb.vif.irq === 1'b1);
          wait_tc(32);
          wait (p_sequencer.traffic_done || p_sequencer.rst_hit);
        join_any
        disable espera;
        if (stop_now()) break;
        wait_tc(pick_delay());
        service_irq();
      end else begin
        wait_tc($urandom_range(cfg().sw_poll_max, 0) + 1);
        if (stop_now()) break;
        wait_tc(pick_delay());
        service_poll();
      end
      if (pct(cfg().reg_noise_pct)) reg_noise();
    end
  endtask

  // ------------------------------------------------ por interrupciones
  task service_irq();
    bit [7:0] iir, dummy;
    wb_read(UART_IIR, iir);
    if (iir[0]) return;                 // nada pendiente
    case (iir[3:1])
      3'b011:           wb_read(UART_LSR, dummy);   // RLS: errores de línea
      3'b010, 3'b110:   read_rx();                // RDA o timeout
      3'b001:           ;                         // THRE: leer IIR ya la limpió
      3'b000:           wb_read(UART_MSR, dummy);   // estado del módem
      default:          `uvm_info("SW", $sformatf("IIR con código raro: %02h", iir), UVM_MEDIUM)
    endcase
  endtask

  // ------------------------------------------------ por sondeo
  task service_poll();
    bit [7:0] lsr, dummy;
    wb_read(UART_LSR, lsr);
    if (lsr[0]) read_rx();
    if ($urandom_range(1)) wb_read(UART_MSR, dummy);
  endtask

  // Vacía la FIFO RX. Normalmente pregunta a LSR antes de cada lectura;
  // a veces lee RBR a ciegas (puede leer con la FIFO vacía) y a veces
  // se detiene antes de vaciarla, para que salga el timeout.
  task read_rx();
    bit [7:0]    lsr, data;
    bit          lsr_first = pct(cfg().sw_lsr_first_pct);
    int unsigned limit     = pct(cfg().sw_partial_pct) ? $urandom_range(ctrl().trigger_level(), 1) : 16;
    for (int i = 0; i < limit; i++) begin
      if (lsr_first) begin
        wb_read(UART_LSR, lsr);
        if (!lsr[0]) break;
      end
      wb_read(UART_RBR, data);
    end
  endtask

  // ------------------------------------------------ ruido de registros
  // Lecturas a cualquier dirección y escrituras solo donde no cambian
  // el formato ni el módem (THR, IER, LSR, MSR, scratch y Debug). Con
  // DLAB = 1 nunca escribimos DLL ni DLM: escribir DLL reinicia el
  // contador de baudios y dañaría el carácter que esté en la línea.
  // El sel inválido (AMB-05) lo mete el driver con +UART_WB_BAD_SEL_PCT;
  // aquí solo le damos permiso donde no hace daño: lecturas, y
  // escrituras a 0..3 con DLAB = 0, que caen en THR. A 4..7 caerían
  // en MCR y con DLAB = 1 en DLL, así que ahí nunca damos permiso.
  task reg_noise();
    bit [4:0]  rd_addr[10] = '{0, 1, 2, 3, 4, 5, 6, 7, 8, 12};
    bit [4:0]  wr_addr[7]  = '{0, 1, 5, 6, 7, 8, 12};
    bit [31:0] rdata;
    if (pct(cfg().reg_dlab_pct)) begin
      // con DLAB = 1: leer cualquier dirección (incluye LSR, MSR e IIR,
      // AMB-07) o escribir donde no pasa nada (LSR, MSR, scratch, Debug)
      bit [4:0] safe_w[5] = '{5, 6, 7, 8, 12};
      lock();
      wb_write(UART_LCR, line().lcr(1'b1), 1);
      if ($urandom_range(1)) wb_acc(0, rd_addr[$urandom_range(9, 0)], 0, rdata, 1);
      else                   wb_acc(1, safe_w[$urandom_range(4, 0)], {24'h0, pick_data()}, rdata, 1);
      wb_write(UART_LCR, line().lcr(1'b0), 1);
      unlock();
    end else if ($urandom_range(1)) begin
      bit [4:0] adr = wr_addr[$urandom_range(6, 0)];
      wb_acc(1, adr, {24'h0, pick_data()}, rdata, 0, adr < 4);
    end else begin
      wb_acc(0, rd_addr[$urandom_range(9, 0)], 0, rdata, 0, 1);
    end
  endtask
endclass : uart_sw_vseq
