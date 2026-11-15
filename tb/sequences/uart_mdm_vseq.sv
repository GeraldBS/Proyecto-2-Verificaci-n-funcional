//////////////////////////////////////////////////////////////////////
// uart_mdm_vseq: cambios en las entradas de módem                  //
//////////////////////////////////////////////////////////////////////
// Cada cambio invierte una entrada (CTS, DSR, RI o DCD) elegida con
// los pesos del knob, y a veces dos a la vez. Así RI sube y baja con
// la misma probabilidad, que es lo que hace falta para ver AMB-04.
//////////////////////////////////////////////////////////////////////
class uart_mdm_vseq extends uart_base_vseq;
  `uvm_object_utils(uart_mdm_vseq)

  int unsigned n_changes;   // lo decide la secuencia principal

  function new(string name = "uart_mdm_vseq");
    super.new(name);
  endfunction

  task body();
    modem_agent_cfg mdm_cfg = cfg().mdm;
    for (int i = 0; i < n_changes && !stop_now(); i++) begin
      mdm_item     item = mdm_item::type_id::create("mdm_item");
      int unsigned sig  = pick_w(mdm_cfg.sig_w);
      start_item(item, -1, p_sequencer.mdm_sqr);
      item.toggle = 4'b0001 << sig;
      if (pct(mdm_cfg.multi_pct)) begin
        int unsigned other = (sig + $urandom_range(3, 1)) % 4;   // otra señal distinta
        item.toggle[other] = 1'b1;
      end
      item.gap_cycles = $urandom_range(mdm_cfg.gap_max, 0) * line().tc_cycles();
      finish_item(item);
    end
  endtask
endclass : uart_mdm_vseq
