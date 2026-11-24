// prueba de humo, lo primero que se corre despues de cualquier cambio al ambiente
class uart_smoke_vseq extends uart_main_vseq;
  `uvm_object_utils(uart_smoke_vseq)

  int unsigned n_chars = 4;

  function new(string name = "uart_smoke_vseq");
    super.new(name);
  endfunction

  task body();
    uvm_reg_hw_reset_seq rs;
    uart_program_vseq    prog = uart_program_vseq::type_id::create("prog");
    uart_rx_vseq         rx   = uart_rx_vseq::type_id::create("rx");
    bit [7:0]            rd, lsr;
    int unsigned         got  = 0;
    uart_line_cfg        lc   = line();
    uart_ctrl_cfg        cc   = ctrl();

    wait (p_sequencer.cfg.wb.vif.rst === 1'b0);
    wait_cycles(2);
    p_sequencer.episode = 1;

    if (p_sequencer.regm != null) begin
      rs = uvm_reg_hw_reset_seq::type_id::create("rs");
      rs.model = p_sequencer.regm;
      rs.start(null, this);
    end

    // 8N1 con DL = 2, nivel de disparo 1, sin interrupciones ni loopback
    lc.wls = 3;  lc.stb = 0;  lc.par_mode = PAR_NONE;
    lc.eps_dc = 0;  lc.sp_dc = 0;
    lc.dl = 2;  lc.dl_lsb_first = 0;
    cc.tl = 0;  cc.rx_clr = 1;  cc.tx_clr = 1;  cc.fcr_dc = 0;
    cc.ier = 0;  cc.ier_dc = 0;
    cc.dtr = 0;  cc.rts = 0;  cc.out1 = 0;  cc.out2 = 0;  cc.loop = 0;
    cc.mcr_dc = 0;
    cfg().cov.sw_mode = SW_POLL;
    prog.start(p_sequencer, this);

    // el scratch es lo mas simple que hay, si esto falla el bus esta mal
    wb_write(UART_SCR, 8'hA5);
    wb_read(UART_SCR, rd);
    if (rd != 8'hA5) `uvm_error("SMOKE", $sformatf("scratch leyo %02h en vez de A5", rd))

    for (int i = 0; i < n_chars; i++) wb_write(UART_THR, pick_data());

    rx.n_chars = n_chars;
    rx.no_errs = 1;
    rx.start(p_sequencer, this);

    // leemos por sondeo lo que llego, con un limite por si nunca llega nada
    for (int i = 0; i < 50 && got < n_chars; i++) begin
      wb_read(UART_LSR, lsr);
      if (lsr[0]) begin
        wb_read(UART_RBR, rd);
        got++;
      end else wait_tc(1);
    end
    if (got != n_chars) `uvm_error("SMOKE", $sformatf("solo se leyeron %0d de %0d caracteres", got, n_chars))

    drain();
    uvm_event_pool::get_global("uart_ep_end").trigger();
    `uvm_info("SMOKE", $sformatf("listo, %0d caracteres por TX y %0d por RX", n_chars, got), UVM_LOW)
  endtask
endclass : uart_smoke_vseq

class uart_smoke_test extends uart_base_test;
  `uvm_component_utils(uart_smoke_test)

  function new(string name = "uart_smoke_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void test_cfg();
    uart_main_vseq::type_id::set_type_override(uart_smoke_vseq::get_type());
  endfunction
endclass : uart_smoke_test
