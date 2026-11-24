class uart_rx_vseq extends uart_base_vseq;
  `uvm_object_utils(uart_rx_vseq)

  int unsigned n_chars;         // lo decide la secuencia principal
  bit          force_errs = 0;  // barrido de formatos: 1ro con paridad mala, 2do con trama mala
  bit          no_errs    = 0;  // despues de un reset solo queremos caracteres buenos

  function new(string name = "uart_rx_vseq");
    super.new(name);
  endfunction

  // un solo numero de 0 a 99 para todos los errores, asi los porcentajes se respetan tal cual
  function uart_ser_err_e pick_err();
    uart_ser_agent_cfg ser_cfg = cfg().ser;
    int unsigned draw = $urandom_range(99);
    int unsigned acc = 0;
    acc += ser_cfg.parity_err_pct; if (draw < acc) return line().pen() ? SER_PARITY : SER_OK;  // sin paridad no hay bit que corromper
    acc += ser_cfg.frame_err_pct;  if (draw < acc) return SER_FRAME;
    acc += ser_cfg.break_pct;      if (draw < acc) return SER_BREAK;
    acc += ser_cfg.glitch_pct;     if (draw < acc) return SER_GLITCH;
    acc += ser_cfg.baud_in_pct;    if (draw < acc) return SER_BAUD_IN;
    acc += ser_cfg.baud_out_pct;   if (draw < acc) return SER_BAUD_OUT;
    return SER_OK;
  endfunction

  // pausa en bits, 0, corta (1-15) o larga (16 a rx_gap_max, más de 4 Tc)
  function int unsigned pick_gap();
    int unsigned a[3] = '{0, 1, 16};
    int unsigned b[3] = '{0, 15, 'hFFFF};
    int unsigned w[]  = new[3];
    w = cfg().ser.rx_gap_w;
    if (cfg().ser.rx_gap_mode == 1) begin   // caracteres pegados, sirve para el overrun
      w[0] = 1; w[1] = 0; w[2] = 0;
    end
    if (cfg().ser.rx_gap_mode == 2) begin   // solo pausas largas, para el timeout
      w[0] = 0; w[1] = 0; w[2] = 1;
    end
    return pick_band3(w, a, b, 0, cfg().ser.rx_gap_max);
  endfunction

  task body();
    uart_ser_agent_cfg ser_cfg = cfg().ser;
    // bits de un carácter completo, para medir el break
    int unsigned char_bits = (16 * (1 + line().data_bits() + line().pen()) + line().stop_ticks() + 15) / 16;
    for (int i = 0; i < n_chars && !stop_now(); i++) begin
      ser_item item = ser_item::type_id::create("ser_item");
      start_item(item, -1, p_sequencer.ser_sqr);
      item.data       = pick_data();
      item.err        = no_errs ? SER_OK : pick_err();
      if (force_errs && i == 0 && line().pen()) item.err = SER_PARITY;
      if (force_errs && i == 1)                 item.err = SER_FRAME;
      item.gap_bits   = pick_gap();
      item.glitch_w   = $urandom_range(ser_cfg.glitch_w_max, 1);
      item.baud_dev   = 0;
      if (item.err == SER_BAUD_IN)  item.baud_dev = $urandom_range(ser_cfg.baud_in_max, 1);
      if (item.err == SER_BAUD_OUT) item.baud_dev = $urandom_range(ser_cfg.baud_out_max, ser_cfg.baud_out_min);
      if ($urandom_range(1)) item.baud_dev = -item.baud_dev;
      item.break_bits = char_bits * (1 + $urandom_range(ser_cfg.break_extra_max, 0)) + 1;
      item.short_stop = !no_errs && line().stb && pct(ser_cfg.short_stop_pct);
      item.dir        = SER_DIR_RX;
      finish_item(item);
    end
  endtask
endclass : uart_rx_vseq
