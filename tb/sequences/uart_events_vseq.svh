//////////////////////////////////////////////////////////////////////
// uart_events_vseq: eventos raros en medio del tráfico             //
//////////////////////////////////////////////////////////////////////
// Con su probabilidad por episodio, y en un momento al azar dentro de
// la ventana del episodio: reconfigurar un registro, limpiar una FIFO
// o dar un reset asíncrono. La secuencia principal decide qué toca.
//////////////////////////////////////////////////////////////////////
class uart_events_vseq extends uart_base_vseq;
  `uvm_object_utils(uart_events_vseq)

  bit          do_reconfig, do_fifo_clr, do_reset;
  int unsigned window_tc;   // los eventos caen entre 0 y window_tc Tc

  function new(string name = "uart_events_vseq");
    super.new(name);
  endfunction

  task body();
    fork
      if (do_reconfig) begin wait_tc($urandom_range(window_tc, 0)); reconfig(); end
      if (do_fifo_clr) begin wait_tc($urandom_range(window_tc, 0)); fifo_clear(); end
      if (do_reset)    begin wait_tc($urandom_range(window_tc, 0)); async_reset(); end
    join
  endtask

  // reescribe LCR, DL, FCR o MCR con valores nuevos. Los agentes ven el
  // formato nuevo de una vez; los caracteres en vuelo quedan como no
  // predecibles para el scoreboard.
  task reconfig();
    if (stop_now()) return;
    case ($urandom_range(3))
      0, 1: begin   // LCR o DL: formato nuevo
        if (!line().randomize()) `uvm_error("RAND", "no se pudo aleatorizar uart_line_cfg")
        if ($urandom_range(1)) write_divisor();
        else begin lock(); wb_write(UART_LCR, line().lcr(1'b0), 1); unlock(); end
      end
      2: begin      // FCR: nivel de disparo nuevo
        if (!ctrl().randomize()) `uvm_error("RAND", "no se pudo aleatorizar uart_ctrl_cfg")
        wb_write(UART_FCR, ctrl().fcr());
      end
      default: begin  // MCR: salidas y loopback
        if (!ctrl().randomize()) `uvm_error("RAND", "no se pudo aleatorizar uart_ctrl_cfg")
        wb_write(UART_MCR, ctrl().mcr());
        cfg().ser.loopback = ctrl().loop;
      end
    endcase
    `uvm_info("EVT", $sformatf("reconfiguración: %s | %s", line().convert2string(),
              ctrl().convert2string()), UVM_MEDIUM)
  endtask

  // limpia la FIFO RX, la TX o las dos, sin cambiar el nivel de disparo
  task fifo_clear();
    bit [7:0] f = {ctrl().tl, 6'b0};
    if (stop_now()) return;
    case ($urandom_range(2))
      0: f[1] = 1;
      1: f[2] = 1;
      2: f[2:1] = 2'b11;
    endcase
    wb_write(UART_FCR, f);
    `uvm_info("EVT", $sformatf("limpieza de FIFO: FCR = %02h", f), UVM_MEDIUM)
  endtask

  // reset asíncrono: sube a una fracción de ciclo cualquiera y dura de
  // 1 a rst_width_max ciclos. Todas las actividades cortan al verlo.
  task async_reset();
    virtual wb_if vif = cfg().wb.vif;
    int unsigned  width = $urandom_range(cfg().rst_width_max, 1);
    if (stop_now()) return;
    #($urandom_range(19, 1) * 1ns);   // no alineado al flanco del reloj
    p_sequencer.rst_hit = 1;
    vif.rst = 1'b1;
    repeat (width) @(posedge vif.clk);
    #($urandom_range(19, 1) * 1ns);
    vif.rst = 1'b0;
    `uvm_info("EVT", $sformatf("reset asíncrono de %0d ciclos", width), UVM_MEDIUM)
  endtask
endclass : uart_events_vseq
