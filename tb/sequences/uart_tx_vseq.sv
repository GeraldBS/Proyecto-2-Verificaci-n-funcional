class uart_tx_vseq extends uart_base_vseq;
  `uvm_object_utils(uart_tx_vseq)

  int unsigned n_bursts;      // lo decide la secuencia principal
  int unsigned max_len = 0;   // 0 = sin tope, con DL lento o despues de reset es 2
  bit          do_break;

  function new(string name = "uart_tx_vseq");
    super.new(name);
  endfunction

  // tx_ovf_pct desborda (17 a 20), el resto se reparte 70 a 15 entre corta y exactamente 16
  function int unsigned pick_len();
    int unsigned len;
    if (pct(cfg().tx_ovf_pct))           len = $urandom_range(cfg().tx_len_max, 17);
    else if ($urandom_range(84) < 70)    len = $urandom_range(15, 1);
    else                                 len = 16;
    if (max_len != 0 && len > max_len) len = $urandom_range(max_len, 1);
    return len;
  endfunction

  // con DL = 0 la FIFO nunca se vacía, así que no esperamos
  task wait_thre();
    bit [7:0] lsr;
    if (line().dl == 0) return;
    forever begin
      if (stop_now()) return;
      wb_read(UART_LSR, lsr);
      if (lsr[5]) return;
      wait_tc($urandom_range(cfg().sw_poll_max, 1));
    end
  endtask

  task body();
    fork
      if (do_break) send_break();
    join_none
    for (int b = 0; b < n_bursts && !stop_now(); b++) begin
      int unsigned len   = pick_len();
      bit          blind = pct(cfg().tx_blind_pct) || (line().dl == 0); // ciega escribe todo aunque se llene la FIFO
      wait_tc($urandom_range(cfg().tx_gap_max, 0));
      for (int i = 0; i < len && !stop_now(); i++) begin
        if (!blind && (i % 16 == 0)) wait_thre();
        wb_write(UART_THR, pick_data());
      end
    end
    wait fork;
  endtask

  task send_break();
    wait_tc($urandom_range(4, 0));
    if (stop_now()) return;
    lock();
    wb_write(UART_LCR, line().lcr(1'b0, 1'b1), 1);  // LCR[6] = 1, stx se va a 0
    unlock();
    wait_tc($urandom_range(cfg().tx_break_max, 1));
    lock();
    wb_write(UART_LCR, line().lcr(1'b0, 1'b0), 1);
    unlock();
  endtask
endclass : uart_tx_vseq
