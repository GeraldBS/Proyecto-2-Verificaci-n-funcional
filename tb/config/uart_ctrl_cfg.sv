//////////////////////////////////////////////////////////////////////
// uart_ctrl_cfg:
// FIFO, interrupciones y módem (FCR, IER, MCR). Se aleatoriza junto
// con uart_line_cfg, los bits que el DUT ignora también se sortean.
//////////////////////////////////////////////////////////////////////
class uart_ctrl_cfg extends uvm_object;
  `uvm_object_utils(uart_ctrl_cfg) // registra en la factory

  // Los bits sin dist salen 50/50
  rand bit [1:0] tl;            // 0...3 = nivel de disparo 1, 4, 8, 14
  rand bit       rx_clr;
  rand bit       tx_clr;
  rand bit [3:0] fcr_dc;        // bits 0, 3, 4, 5 de FCR (el DUT los ignora)
  rand bit [3:0] ier;           // RDA, THRE, RLS, MS
  rand bit [3:0] ier_dc;        // bits 7:4 de IER (reservados)
  rand bit       dtr;
  rand bit       rts;
  rand bit       out1;
  rand bit       out2;
  rand bit       loop;
  rand bit [2:0] mcr_dc;        // bits 7:5 de MCR

  // knobs
  int          fcr_tl       = -1;   // -1 lo sortea, 0 a 3 lo fija
  bit [3:0]    ier_on       = 4'h0; // bits de IER que siempre van en 1
  int unsigned mcr_loop_pct = 20;

  // limites de los knobs
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

  // byte de FCR
  function bit [7:0] fcr();
    bit [7:0] v = '0;
    v[UART_FCR_EN]     = fcr_dc[0];
    v[UART_FCR_RXCLR]  = rx_clr;
    v[UART_FCR_TXCLR]  = tx_clr;
    v[UART_FCR_DMA]    = fcr_dc[1];
    v[5:4]             = fcr_dc[3:2];
    v[UART_FCR_TL +: 2] = tl;
    return v;
  endfunction

  function bit [7:0] ier_byte(); return {ier_dc, ier}; endfunction

  // byte de MCR
  function bit [7:0] mcr();
    bit [7:0] v = '0;
    v[UART_MCR_DTR]  = dtr;
    v[UART_MCR_RTS]  = rts;
    v[UART_MCR_OUT1] = out1;
    v[UART_MCR_OUT2] = out2;
    v[UART_MCR_LOOP] = loop;
    v[7:5]           = mcr_dc;
    return v;
  endfunction

  // imprime respuestas
  function string convert2string();
    return $sformatf("TL=%0d clr(rx,tx)=%0b%0b IER=%04b MCR=%05b%s", trigger_level(),
                     rx_clr, tx_clr, ier, {loop, out2, out1, rts, dtr}, loop ? " LOOPBACK" : "");
  endfunction
endclass : uart_ctrl_cfg