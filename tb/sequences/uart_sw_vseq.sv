class uart_sw_vseq extends uart_base_vseq;
  `uvm_object_utils(uart_sw_vseq)

  uart_sw_mode_e mode;   // lo decide la secuencia principal

  function new(string name = "uart_sw_vseq");
    super.new(name);
  endfunction

  // retraso de atencion en Tc, corto (0-1), medio (2-6) o largo (7-24)
  function int unsigned pick_delay();
    int unsigned band_lo[3] = '{0, 2, 7};
    int unsigned band_hi[3] = '{1, 6, 'hFFFF};
    return pick_band3(cfg().sw_delay_w, band_lo, band_hi, cfg().sw_delay_min, cfg().sw_delay_max);
  endfunction

  task body();
    while (!p_sequencer.traffic_done && !stop_now()) begin
      if (mode == SW_IRQ) begin
        fork : espera   // respaldo cada 32 Tc por si IER = 0 o se perdio el aviso
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

  task service_poll();
    bit [7:0] lsr, dummy;
    wb_read(UART_LSR, lsr);
    if (lsr[0]) read_rx();
    if ($urandom_range(1)) wb_read(UART_MSR, dummy);
  endtask

  // a veces lee RBR a ciegas o deja datos en la FIFO para que salga el timeout
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

  // escribir DLL reinicia el contador de baudios y daña el caracter en la linea, por eso con DLAB = 1 nunca se escribe 0 ni 1
  task reg_noise();
    bit [4:0]  rd_addr[10] = '{0, 1, 2, 3, 4, 5, 6, 7, 8, 12};
    bit [4:0]  wr_addr[7]  = '{0, 1, 5, 6, 7, 8, 12};
    bit [31:0] rdata;
    if (pct(cfg().reg_dlab_pct)) begin
      bit [4:0] safe_w[5] = '{5, 6, 7, 8, 12};   // donde escribir no hace nada raro (AMB-07)
      lock();
      wb_write(UART_LCR, line().lcr(1'b1), 1);
      if ($urandom_range(1)) wb_acc(0, rd_addr[$urandom_range(9, 0)], 0, rdata, 1);
      else                   wb_acc(1, safe_w[$urandom_range(4, 0)], {24'h0, pick_data()}, rdata, 1);
      wb_write(UART_LCR, line().lcr(1'b0), 1);
      unlock();
    end else if ($urandom_range(1)) begin
      bit [4:0] adr = wr_addr[$urandom_range(6, 0)];
      wb_acc(1, adr, {24'h0, pick_data()}, rdata, 0, adr < 4);  // sel malo solo en 0..3, que caen en THR (AMB-05)
    end else begin
      wb_acc(0, rd_addr[$urandom_range(9, 0)], 0, rdata, 0, 1);
    end
  endtask
endclass : uart_sw_vseq
