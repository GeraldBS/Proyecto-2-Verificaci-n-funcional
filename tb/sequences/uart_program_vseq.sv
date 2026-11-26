//////////////////////////////////////////////////////////////////
// uart_program_vseq:
// Programa el UART por Wishbone al inicio de cada episodio y después de un
// reset. Escribe el divisor y el LCR con la secuencia de DLAB, y luego FCR,
// IER y MCR
//////////////////////////////////////////////////////////////////

class uart_program_vseq extends uart_base_vseq; // secuencia de programación del UART
  `uvm_object_utils(uart_program_vseq) // macro para registrar la clase en el factory

  function new(string name = "uart_program_vseq"); // constructor
    super.new(name);
  endfunction

  task body();  // tarea principal de la secuencia
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