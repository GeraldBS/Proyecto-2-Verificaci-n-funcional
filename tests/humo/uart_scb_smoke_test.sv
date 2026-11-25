// humo de la parte serie, el modem y el scoreboard, para ver que el scoreboard de verdad compara

// cuatro formatos fijos, 3 caracteres por TX y 3 por RX en cada uno, sin errores
class uart_ser_smoke_vseq extends uart_main_vseq;
  `uvm_object_utils(uart_ser_smoke_vseq)

  int unsigned n_chars = 3;

  function new(string name = "uart_ser_smoke_vseq");
    super.new(name);
  endfunction

  // un caracter bueno por srx, con poco espacio para que no tarde
  task send_rx(bit [7:0] data);
    ser_item item = ser_item::type_id::create("ser_item");
    start_item(item, -1, p_sequencer.ser_sqr);
    item.data       = data;
    item.err        = SER_OK;
    item.gap_bits   = 1;
    item.glitch_w   = 1;
    item.baud_dev   = 0;
    item.break_bits = 0;
    item.short_stop = 0;
    item.dir        = SER_DIR_RX;
    finish_item(item);
  endtask

  task body();
    uvm_reg_hw_reset_seq rs;
    uart_program_vseq    prog;
    bit [7:0]            rd, lsr;
    int unsigned         got;
    uart_line_cfg        lc = line();
    uart_ctrl_cfg        cc = ctrl();
    // wls, stb y paridad de cada formato: 5N1, 6O2, 7E2, 8 con paridad fija en 1
    bit [1:0]  wls[4] = '{0, 1, 2, 3};
    bit        stb[4] = '{0, 1, 1, 0};
    uart_par_e par[4] = '{PAR_NONE, PAR_ODD, PAR_EVEN, PAR_STICK1};

    wait (p_sequencer.cfg.wb.vif.rst === 1'b0);
    wait_cycles(2);

    if (p_sequencer.regm != null) begin
      rs = uvm_reg_hw_reset_seq::type_id::create("rs");
      rs.model = p_sequencer.regm;
      rs.start(null, this);
    end

    cc.tl = 0;  cc.rx_clr = 1;  cc.tx_clr = 1;  cc.fcr_dc = 0;
    cc.ier = 0;  cc.ier_dc = 0;
    cc.dtr = 0;  cc.rts = 0;  cc.out1 = 0;  cc.out2 = 0;  cc.loop = 0;
    cc.mcr_dc = 0;
    cfg().cov.sw_mode = SW_POLL;

    foreach (wls[f]) begin
      p_sequencer.episode = f + 1;
      lc.wls = wls[f];  lc.stb = stb[f];  lc.par_mode = par[f];
      lc.eps_dc = 0;  lc.sp_dc = 0;
      lc.dl = 2;  lc.dl_lsb_first = 0;
      prog = uart_program_vseq::type_id::create("prog");
      prog.start(p_sequencer, this);

      for (int i = 0; i < n_chars; i++) wb_write(UART_THR, pick_data());
      for (int i = 0; i < n_chars; i++) send_rx(pick_data());

      // leemos por sondeo con un limite por si no llega nada
      got = 0;
      for (int i = 0; i < 50 && got < n_chars; i++) begin
        wb_read(UART_LSR, lsr);
        if (lsr[0]) begin
          wb_read(UART_RBR, rd);
          got++;
        end else wait_tc(1);
      end
      if (got != n_chars) `uvm_error("SMOKE", $sformatf("%s: solo se leyeron %0d de %0d", lc.convert2string(), got, n_chars))

      drain();
      uvm_event_pool::get_global("uart_ep_end").trigger();
    end
  endtask
endclass : uart_ser_smoke_vseq

class uart_ser_smoke_test extends uart_base_test;
  `uvm_component_utils(uart_ser_smoke_test)

  function new(string name = "uart_ser_smoke_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void test_cfg();
    uart_main_vseq::type_id::set_type_override(uart_ser_smoke_vseq::get_type());
  endfunction

  // el check_phase del scoreboard ya corrio, aqui solo vemos que haya comparado todo
  function void check_phase(uvm_phase phase);
    int unsigned total = 4 * 3;
    super.check_phase(phase);
    if (env.scb.n_tx_ok != total || env.scb.n_rx_ok != total || env.scb.n_skip != 0)
      `uvm_error("SMOKE", $sformatf("el scoreboard comparo TX %0d y RX %0d de %0d, sin comparar %0d",
                 env.scb.n_tx_ok, env.scb.n_rx_ok, total, env.scb.n_skip))
  endfunction
endclass : uart_ser_smoke_test


// rts y dtr, las cuatro combinaciones de MCR[1:0] y despues de vuelta a 0
class uart_mdm_smoke_vseq extends uart_main_vseq;
  `uvm_object_utils(uart_mdm_smoke_vseq)

  function new(string name = "uart_mdm_smoke_vseq");
    super.new(name);
  endfunction

  task body();
    bit [7:0] rd;
    bit [7:0] valores[4] = '{8'h01, 8'h02, 8'h03, 8'h00};

    wait (p_sequencer.cfg.wb.vif.rst === 1'b0);
    wait_cycles(2);
    p_sequencer.episode = 1;

    foreach (valores[i]) begin
      wb_write(UART_MCR, valores[i]);
      // el scoreboard revisa los pines en el siguiente acceso, por eso leemos el scratch
      wb_read(UART_SCR, rd);
    end
    uvm_event_pool::get_global("uart_ep_end").trigger();
  endtask
endclass : uart_mdm_smoke_vseq

class uart_mdm_smoke_test extends uart_base_test;
  `uvm_component_utils(uart_mdm_smoke_test)

  function new(string name = "uart_mdm_smoke_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void test_cfg();
    uart_main_vseq::type_id::set_type_override(uart_mdm_smoke_vseq::get_type());
  endfunction

  // con el RTL actual las 4 salen como AMB-03, lo que importa es que se revisaron las 4
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (env.scb.n_mdm_ok + env.scb.n_mdm_amb != 4)
      `uvm_error("SMOKE", $sformatf("el scoreboard reviso rts/dtr %0d veces y se esperaban 4",
                 env.scb.n_mdm_ok + env.scb.n_mdm_amb))
  endfunction
endclass : uart_mdm_smoke_test
