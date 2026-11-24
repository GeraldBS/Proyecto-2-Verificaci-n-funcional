//////////////////////////////////////////////////////////////////////
// uart_ser_sva: aserciones de la línea serie, el módem, el reset y  
// la interrupción del UART 16550 (sección 11 del plan)           
//////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`include "uart_defines.v"

module uart_ser_sva (
  input logic                            wb_clk_i,
  input logic                            wb_rst_i,
  // Pines del DUT
  input logic                            stx_pad_o,
  input logic                            srx_pad_i,
  input logic                            rts_pad_o,
  input logic                            dtr_pad_o,
  input logic                            cts_pad_i,
  input logic                            dsr_pad_i,
  input logic                            ri_pad_i,
  input logic                            dcd_pad_i,
  input logic                            int_o,
  // Registros internos de uart_top.regs
  input logic [7:0]                      lcr,
  input logic [4:0]                      mcr,
  input logic [15:0]                     dl,
  input logic [3:0]                      iir,
  input logic [7:0]                      msr,
  // Transmisor (uart_top.regs)
  input logic [2:0]                      tstate,
  input logic [`UART_FIFO_COUNTER_W-1:0] tf_count
);

  default clocking cb @(posedge wb_clk_i); endclocking
  default disable iff (wb_rst_i);

  // Estados del transmisor (uart_transmitter.v)
  localparam logic [2:0] S_IDLE   = 3'd0;
  localparam logic [2:0] S_START  = 3'd1;
  localparam logic [2:0] S_BYTE   = 3'd2;
  localparam logic [2:0] S_PARITY = 3'd3;
  localparam logic [2:0] S_STOP   = 3'd4;
  localparam logic [2:0] S_POP    = 3'd5;

  string dut_bug_sev = "warning";
  initial begin
    string s;
    if ($value$plusargs("UART_SCB_DUT_BUG_SEV=%s", s)) dut_bug_sev = s;
  end

  int unsigned n_fail = 0;       // aserciones falladas 
  int unsigned n_dut_bug = 0;    // diferencias conocidas del DUT

  function automatic void rep_err(string id, string msg);
    n_fail++;
`ifdef UART_SVA_NO_UVM
    $display("[SVA_FAIL] %s: %s (t=%0t)", id, msg, $time);
`else
    uvm_pkg::uvm_report_error(id, msg, uvm_pkg::UVM_NONE);
`endif
  endfunction

  function automatic void rep_dut_bug(string id, string msg);
    n_dut_bug++;
`ifdef UART_SVA_NO_UVM
    $display("[SVA_DUT_BUG] %s: %s (t=%0t)", id, msg, $time);
`else
    if (dut_bug_sev == "error") uvm_pkg::uvm_report_error  (id, msg, uvm_pkg::UVM_NONE);
    else                        uvm_pkg::uvm_report_warning(id, msg, uvm_pkg::UVM_NONE);
`endif
  endfunction

  // A-SER-01
  property p_ser01_idle;
    (!lcr[6] && (tstate == S_IDLE || tstate == S_POP)) |-> stx_pad_o;
  endproperty
  a_ser01_idle: assert property (p_ser01_idle)
    else rep_err("A-SER-01", "stx no está en 1 sin carácter en curso");
  c_ser01_idle: cover property (!lcr[6] && tstate == S_IDLE && stx_pad_o ##1 tstate == S_POP);

  
  property p_ser01_dl0;
    ($past(dl == 16'd0) && stx_pad_o && !lcr[6]) |=> (stx_pad_o || lcr[6]);
  endproperty
  a_ser01_dl0: assert property (p_ser01_dl0)
    else rep_err("A-SER-01", "stx bajó con DL = 0");
  c_ser01_dl0: cover property ((dl == 16'd0 && tf_count != 0 && stx_pad_o) [*8]);

 
  // A-SER-02
  logic        stx_q;
  logic [31:0] low_len;     // ciclos seguidos con stx en 0
  logic [15:0] low_dl;      // DL con que empezó la racha
  logic        low_clean;   // racha sin cambios de DL, break ni loopback

  always_ff @(posedge wb_clk_i or posedge wb_rst_i) begin
    if (wb_rst_i) begin
      stx_q     <= 1'b1;
      low_len   <= '0;
      low_dl    <= '0;
      low_clean <= 1'b0;
    end else begin
      stx_q <= stx_pad_o;
      if (!stx_pad_o) begin
        if (stx_q) begin                       // flanco de bajada: empieza el bit de inicio
          low_len   <= 32'd1;
          low_dl    <= dl;
          low_clean <= !lcr[6] && !mcr[4];
        end else begin
          low_len <= low_len + 32'd1;
          if (dl != low_dl || lcr[6] || mcr[4]) low_clean <= 1'b0;
        end
      end else if (stx_q) begin
        low_len <= '0;                         // se conserva un ciclo para la aserción
      end
    end
  end

  wire stx_rise = stx_pad_o && !stx_q;

  wire low_ok = low_clean && dl == low_dl && !lcr[6] && !mcr[4];

  property p_ser02_width;
    (stx_rise && low_ok && low_dl != 16'd0) |->
      (low_len >= 32'd16 * low_dl) && (low_len % (32'd16 * low_dl) == 0);
  endproperty
  a_ser02_width: assert property (p_ser02_width)
    else rep_err("A-SER-02", $sformatf("racha en 0 de %0d ciclos con DL = %0d (se esperaba un múltiplo de %0d)",
                                       low_len, low_dl, 16 * low_dl));
  c_ser02_dl1:   cover property (stx_rise && low_ok && low_dl == 16'd1);
  c_ser02_dlgt16: cover property (stx_rise && low_ok && low_dl > 16'd16);

  // A-SER-03
  a_ser03_loop: assert property (mcr[4] |-> stx_pad_o)
    else rep_err("A-SER-03", "stx no está en 1 en loopback");
  c_ser03_loop: cover property (mcr[4] && tstate != S_IDLE && stx_pad_o);   // con un carácter en curso

  // A-SER-04
  a_ser04_break: assert property ((lcr[6] && !mcr[4]) |-> !stx_pad_o)
    else rep_err("A-SER-04", "stx no está en 0 con LCR[6] = 1");
  c_ser04_break: cover property ($rose(lcr[6]) && !mcr[4] && (tstate == S_START || tstate == S_BYTE || tstate == S_PARITY || tstate == S_STOP));   // break a mitad de carácter

  // A-RST-01
  property p_rst01;
    @(posedge wb_clk_i) disable iff (1'b0)
      (wb_rst_i || $fell(wb_rst_i)) |-> (stx_pad_o && !int_o);
  endproperty
  a_rst01: assert property (p_rst01)
    else rep_err("A-RST-01", "stx o int_o incorrectos después del reset");
  c_rst01: cover property (@(posedge wb_clk_i) disable iff (1'b0) wb_rst_i && !$past(wb_rst_i) && $past(tstate) != S_IDLE);   // reset con tráfico

  // A-INT-01
  localparam int unsigned INT_WIN = 2;

  wire         int_mm_now = (int_o == iir[0]);   // int_o debería ser el complemento de IIR[0]
  logic [7:0]  int_mm_q;                         // ciclos seguidos anteriores con desajuste

  always_ff @(posedge wb_clk_i or posedge wb_rst_i) begin
    if (wb_rst_i)                          int_mm_q <= '0;
    else if (!int_mm_now)                  int_mm_q <= '0;
    else if (int_mm_q != 8'hFF)            int_mm_q <= int_mm_q + 8'd1;
  end

  a_int01: assert property (!(int_mm_now && int_mm_q == INT_WIN))
    else rep_err("A-INT-01", $sformatf("int_o = %b con IIR = %h durante más de %0d ciclos", int_o, iir, INT_WIN));
  c_int_rise: cover property ($rose(int_o));
  c_int_fall: cover property ($fell(int_o));
  c_int_lag:  cover property (int_mm_now ##1 !int_mm_now);   // la ventana de tolerancia sí se usa

  // A-MDM-01
  property p_mdm01;
    ($fell(wb_rst_i) || $changed(mcr[1:0])) |-> ({rts_pad_o, dtr_pad_o} == ~{mcr[1], mcr[0]});
  endproperty
  a_mdm01: assert property (@(posedge wb_clk_i) disable iff (1'b0) p_mdm01)
    else rep_dut_bug("AMB-03", $sformatf("rts/dtr = %b%b con MCR[1:0] = %b%b (se esperaba el complemento)", rts_pad_o, dtr_pad_o, mcr[1], mcr[0]));
  c_mdm01_rts: cover property ($changed(rts_pad_o));
  c_mdm01_dtr: cover property ($changed(dtr_pad_o));

  // A-MDM-02
  property p_mdm02;
    mcr[4] |=> (msr[7:4] == $past({mcr[3], mcr[2], mcr[0], mcr[1]}));
  endproperty
  a_mdm02: assert property (p_mdm02)
    else rep_err("A-MDM-02", "MSR[7:4] distinto de OUT2, OUT1, DTR, RTS en loopback");
  c_mdm02: cover property (mcr[4] ##1 mcr[4] && msr[7:4] != 4'h0);

  // A-ENV-01
  a_env01: assume property (!$isunknown({srx_pad_i, cts_pad_i, dsr_pad_i, ri_pad_i, dcd_pad_i}));
  c_env01: cover property (!$isunknown({srx_pad_i, cts_pad_i, dsr_pad_i, ri_pad_i, dcd_pad_i}));

endmodule : uart_ser_sva
