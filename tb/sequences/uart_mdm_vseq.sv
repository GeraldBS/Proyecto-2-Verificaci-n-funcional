//////////////////////////////////////////////////////////////////
// uart_mdm_vseq:
// Cambios de las entradas de módem (CTS, DSR, RI y DCD) de un episodio.
// Manda n cambios al agente de módem
//////////////////////////////////////////////////////////////////

class uart_mdm_vseq extends uart_base_vseq; // se crea la secuencia de cambios 
  `uvm_object_utils(uart_mdm_vseq) // se crea el objeto

  int unsigned n_changes;   // lo decide la secuencia principal

  function new(string name = "uart_mdm_vseq"); // constructor
    super.new(name);
  endfunction

  task body(); // se realiza el cuerpo en tiempo de ejecucuion
    modem_agent_cfg mdm_cfg = cfg().mdm;
    for (int i = 0; i < n_changes && !stop_now(); i++) begin // se recorre toda la secuencia
      mdm_item     item = mdm_item::type_id::create("mdm_item");
      int unsigned sig  = pick_w(mdm_cfg.sig_w);
      start_item(item, -1, p_sequencer.mdm_sqr); // se inicia el item
      item.toggle = 4'b0001 << sig;
      if (pct(mdm_cfg.multi_pct)) begin
        int unsigned other = (sig + $urandom_range(3, 1)) % 4;   // otra señal distinta
        item.toggle[other] = 1'b1;
      end
      item.gap_cycles = $urandom_range(mdm_cfg.gap_max, 0) * line().tc_cycles();
      finish_item(item); // se termina el item
    end
  endtask
endclass : uart_mdm_vseq