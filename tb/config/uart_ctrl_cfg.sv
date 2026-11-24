class uart_ctrl_cfg extends uvm_object;
  `uvm_object_utils(uart_ctrl_cfg)

  // configuración (aleatoria), los bits sin dist salen 50/50
  rand bit [1:0] tl;            // 0...3 = nivel de disparo 1, 4, 8, 14
  rand bit       rx_clr, tx_clr;
  rand bit [3:0] fcr_dc;        // bits 0, 3, 4, 5 de FCR (el DUT los ignora)
  rand bit [3:0] ier;           // RDA, THRE, RLS, MS
  rand bit [3:0] ier_dc;        // bits 7:4 de IER (reservados)
  rand bit       dtr, rts, out1, out2, loop;
  rand bit [2:0] mcr_dc;        // bits 7:5 de MCR

  // knobs
  int          fcr_tl       = -1;   // -1 lo sortea, 0 a 3 lo fija
  bit [3:0]    ier_on       = 4'h0; // bits de IER que siempre van en 1
  int unsigned mcr_loop_pct = 20;

  constraint c_tl   { if (fcr_tl >= 0) tl == fcr_tl; }
  constraint c_ier  { (ier & ier_on) == ier_on; }
  constraint c_loop { loop dist { 1 := mcr_loop_pct, 0 := 100 - mcr_loop_pct }; }

  function new(string name = "uart_ctrl_cfg"); // constructor
    super.new(name);
  endfunction

  function int unsigned trigger_level();
    case (tl)
      2'd0: return 1;
      2'd1: return 4;
      2'd2: return 8;
      default: return 14;
    endcase
  endfunction

  function bit [7:0] fcr();
    return {tl, fcr_dc[3:2], fcr_dc[1], tx_clr, rx_clr, fcr_dc[0]};
  endfunction

  function bit [7:0] ier_byte(); return {ier_dc, ier}; endfunction

  function bit [7:0] mcr();
    return {mcr_dc, loop, out2, out1, rts, dtr};
  endfunction

  function string convert2string();
    return $sformatf("TL=%0d clr(rx,tx)=%0b%0b IER=%04b MCR=%05b%s", trigger_level(),
                     rx_clr, tx_clr, ier, {loop, out2, out1, rts, dtr}, loop ? " LOOPBACK" : "");
  endfunction
endclass : uart_ctrl_cfg
