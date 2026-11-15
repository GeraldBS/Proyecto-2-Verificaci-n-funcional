//////////////////////////////////////////////////////////////////////
// uart_tx_vseq: tráfico de transmisión (escrituras a THR)          //
//////////////////////////////////////////////////////////////////////
// Manda n_bursts ráfagas. Una ráfaga "ciega" escribe todo de una vez
// aunque la FIFO se llene (así se pierden datos a propósito). Una
// ráfaga normal espera THRE y escribe de a 16 como lo haría un driver
// de verdad. El break (LCR[6]) se activa un rato en un momento al azar.
//////////////////////////////////////////////////////////////////////
class uart_tx_vseq extends uart_base_vseq;
  `uvm_object_utils(uart_tx_vseq)

  int unsigned n_bursts;      // lo decide la secuencia principal
  bit          do_break;

  function new(string name = "uart_tx_vseq");
    super.new(name);
  endfunction

  // largo de una ráfaga: corta, exactamente 16, o más de 16
  function int unsigned pick_len();
    case (pick_w(cfg().tx_len_w))
      0:       return $urandom_range(15, 1);
      1:       return 16;
      default: return $urandom_range(cfg().tx_len_max, 17);
    endcase
  endfunction

  // espera THRE leyendo LSR; con DL = 0 nunca se vacía, así que no esperamos
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
      // con DL = 0 la FIFO no se vacía: solo tiene sentido escribir a ciegas
      bit          blind = pct(cfg().tx_blind_pct) || (line().dl == 0);
      wait_tc($urandom_range(cfg().tx_gap_max, 0));
      for (int i = 0; i < len && !stop_now(); i++) begin
        if (!blind && (i % 16 == 0)) wait_thre();
        wb_write(UART_THR, pick_data());
      end
    end
    wait fork;
  endtask

  // break en TX: LCR[6] = 1 durante 1 a tx_break_max Tc
  task send_break();
    wait_tc($urandom_range(4, 0));
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
