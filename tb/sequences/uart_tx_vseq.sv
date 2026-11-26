//////////////////////////////////////////////////////////////////
// uart_tx_vseq:
// Ráfagas de escritura a THR de un episodio, con o sin revisar THRE antes.
// Algunas ráfagas son de 17 a 20 caracteres para desbordar la FIFO TX
//////////////////////////////////////////////////////////////////

class uart_tx_vseq extends uart_base_vseq; // secuencia de ráfagas de escritura a THR
  `uvm_object_utils(uart_tx_vseq)

  int unsigned n_bursts;      // lo decide la secuencia principal
  int unsigned max_len = 0;   // 0 = sin tope, con DL lento o después de un reset es 2
  bit do_break;      // lo decide la secuencia principal 

  function new(string name = "uart_tx_vseq");
    super.new(name);
  endfunction

  function int unsigned pick_len(); // tx_ovf_pct desborda (17 a 20), el resto se reparte 70 a 15 entre corta y exactamente 16
    int unsigned len;
    if (pct(cfg().tx_ovf_pct))           len = $urandom_range(cfg().tx_len_max, 17);
    else if ($urandom_range(84) < 70)    len = $urandom_range(15, 1);
    else                                 len = 16;
    if (max_len != 0 && len > max_len) len = $urandom_range(max_len, 1);   // tope por DL lento o por reset
    return len;
  endfunction

  task wait_thre(); // espera a que THRE (LSR[5]) indique FIFO TX vacía, con DL = 0 nunca se vacía, así que no espera
    bit [7:0] lsr;
    if (line().dl == 0) return;
    forever begin
      if (stop_now()) return;
      wb_read(UART_LSR, lsr);
      if (lsr[5]) return;
      wait_tc($urandom_range(cfg().sw_poll_max, 1));   // mínimo 1 para no repetir en el mismo instante
    end
  endtask

  task body(); // ráfagas de escritura a THR, con o sin revisar THRE antes, con o sin break
    fork
      if (do_break) send_break();
    join_none // el break puede ocurrir en cualquier momento por eso el none
    for (int b = 0; b < n_bursts && !stop_now(); b++) begin
      int unsigned len   = pick_len();
      bit          blind = pct(cfg().tx_blind_pct) || (line().dl == 0);   
      wait_tc($urandom_range(cfg().tx_gap_max, 0)); // pausa entre ráfagas
      for (int i = 0; i < len && !stop_now(); i++) begin
        if (!blind && (i % 16 == 0)) wait_thre();  // la FIFO cabe 16, revisa antes de cada grupo
        wb_write(UART_THR, pick_data());
      end
    end
    wait fork;   // espera también el break, si lo hubo
  endtask

  task send_break(); 
    wait_tc($urandom_range(4, 0));   // arranca en un momento cualquiera del episodio
    if (stop_now()) return;
    lock();
    wb_write(UART_LCR, line().lcr(1'b0, 1'b1), 1);
    unlock();
    wait_tc($urandom_range(cfg().tx_break_max, 1));
    lock();
    wb_write(UART_LCR, line().lcr(1'b0, 1'b0), 1);
    unlock();
  endtask
endclass : uart_tx_vseq