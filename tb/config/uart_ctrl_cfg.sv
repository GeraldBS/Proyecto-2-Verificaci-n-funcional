//////////////////////////////////////////////////////////////////////
// uart_ctrl_cfg: FIFO, interrupciones y módem (FCR, IER, MCR)      //
//////////////////////////////////////////////////////////////////////
// Se aleatoriza junto con uart_line_cfg al inicio de cada episodio.
// Los bits que el DUT ignora también se aleatorizan, así se mueven
// todos los bits del bus y ayuda al toggle.
//////////////////////////////////////////////////////////////////////
class uart_ctrl_cfg extends uvm_object;
  `uvm_object_utils(uart_ctrl_cfg)

  // ---------------- configuración (aleatoria) ----------------
  rand bit [1:0] tl;            // 0..3 = nivel de disparo 1, 4, 8, 14
  rand bit       rx_clr, tx_clr;
  rand bit [3:0] fcr_dc;        // bits 0, 3, 4, 5 de FCR (el DUT los ignora)
  rand bit [3:0] ier;           // RDA, THRE, RLS, MS
  rand bit [3:0] ier_dc;        // bits 7:4 de IER (reservados)
  rand bit       dtr, rts, out1, out2, loop;
  rand bit [2:0] mcr_dc;        // bits 7:5 de MCR

  // ---------------- knobs ----------------
  int unsigned tl_w[]        = '{1, 1, 1, 1};
  int unsigned fcr_clr_pct   = 50;
  int unsigned ier_bit_pct[] = '{50, 50, 50, 50};
  int unsigned mcr_out_pct   = 50;
  int unsigned mcr_loop_pct  = 20;

  constraint c_tl  { tl dist { 0 := tl_w[0], 1 := tl_w[1], 2 := tl_w[2], 3 := tl_w[3] }; }
  constraint c_clr {
    rx_clr dist { 1 := fcr_clr_pct, 0 := 100 - fcr_clr_pct };
    tx_clr dist { 1 := fcr_clr_pct, 0 := 100 - fcr_clr_pct };
  }
  // un dist por bit para que cada bit de IER sea independiente
  constraint c_ier {
    foreach (ier[i]) ier[i] dist { 1 := ier_bit_pct[i], 0 := 100 - ier_bit_pct[i] };
  }
  constraint c_mcr {
    dtr  dist { 1 := mcr_out_pct,  0 := 100 - mcr_out_pct };
    rts  dist { 1 := mcr_out_pct,  0 := 100 - mcr_out_pct };
    out1 dist { 1 := mcr_out_pct,  0 := 100 - mcr_out_pct };
    out2 dist { 1 := mcr_out_pct,  0 := 100 - mcr_out_pct };
    loop dist { 1 := mcr_loop_pct, 0 := 100 - mcr_loop_pct };
  }

  function new(string name = "uart_ctrl_cfg");
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
