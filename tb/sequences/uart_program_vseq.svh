//////////////////////////////////////////////////////////////////////
// uart_program_vseq: programa el UART con la configuración vigente //
//////////////////////////////////////////////////////////////////////
// Sigue la sección 5.1 de la spec: divisor con DLAB = 1, LCR con
// DLAB = 0, FCR y IER, y además MCR. Todo con el candado del bus,
// así ninguna otra actividad se mete en medio.
//////////////////////////////////////////////////////////////////////
class uart_program_vseq extends uart_base_vseq;
  `uvm_object_utils(uart_program_vseq)

  function new(string name = "uart_program_vseq");
    super.new(name);
  endfunction

  task body();
    lock();
    write_divisor(1);
    wb_write(UART_FCR, ctrl().fcr(),      1);
    wb_write(UART_IER, ctrl().ier_byte(), 1);
    wb_write(UART_MCR, ctrl().mcr(),      1);
    unlock();
    // en loopback el agente serie deja srx en reposo
    cfg().ser.loopback = ctrl().loop;
    `uvm_info("PROG", $sformatf("episodio %0d: %s | %s", p_sequencer.episode,
              line().convert2string(), ctrl().convert2string()), UVM_MEDIUM)
  endtask
endclass : uart_program_vseq
