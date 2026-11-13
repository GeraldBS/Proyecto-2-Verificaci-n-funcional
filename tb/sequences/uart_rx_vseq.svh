//////////////////////////////////////////////////////////////////////
// uart_rx_vseq: caracteres que el agente serie manda al UART       //
//////////////////////////////////////////////////////////////////////
// Arma cada ser_item con los knobs del agente serie: dato, pausa
// antes del carácter y el error a inyectar. El error se sortea con un
// solo número de 0 a 99, así los porcentajes se respetan tal cual.
//////////////////////////////////////////////////////////////////////
class uart_rx_vseq extends uart_base_vseq;
  `uvm_object_utils(uart_rx_vseq)

  int unsigned n_chars;   // lo decide la secuencia principal

  function new(string name = "uart_rx_vseq");
    super.new(name);
  endfunction

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

  // pausa en bits: 0, corta (1-15) o larga (16 a rx_gap_max, más de 4 Tc)
  function int unsigned pick_gap();
    int unsigned a[3] = '{0, 1, 16};
    int unsigned b[3] = '{0, 15, 'hFFFF};
    return pick_band3(cfg().ser.rx_gap_w, a, b, 0, cfg().ser.rx_gap_max);
  endfunction

  task body();
    uart_ser_agent_cfg ser_cfg = cfg().ser;
    // bits de un carácter completo, para medir el break
    int unsigned char_bits = (16 * (1 + line().data_bits() + line().pen()) + line().stop_ticks() + 15) / 16;
    for (int i = 0; i < n_chars && !stop_now(); i++) begin
      ser_item item = ser_item::type_id::create("ser_item");
      start_item(item, -1, p_sequencer.ser_sqr);
      item.data       = pick_data();
      item.err        = pick_err();
      item.gap_bits   = pick_gap();
      item.glitch_w   = $urandom_range(ser_cfg.glitch_w_max, 1);
      item.baud_dev   = 0;
      if (item.err == SER_BAUD_IN)  item.baud_dev = $urandom_range(ser_cfg.baud_in_max, 1);
      if (item.err == SER_BAUD_OUT) item.baud_dev = $urandom_range(ser_cfg.baud_out_max, ser_cfg.baud_out_min);
      if ($urandom_range(1)) item.baud_dev = -item.baud_dev;
      item.break_bits = char_bits * (1 + $urandom_range(ser_cfg.break_extra_max, 0)) + 1;
      item.short_stop = line().stb && pct(ser_cfg.short_stop_pct);
      item.dir        = SER_DIR_RX;
      finish_item(item);
    end
  endtask
endclass : uart_rx_vseq
