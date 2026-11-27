`timescale 1ns/1ps
`include "uart_defines.v"

module tb_sva_smoke;

  logic clk = 1'b0;
  always #10 clk = ~clk; // 50 MHz

  logic                        rst;
  logic [`UART_ADDR_WIDTH-1:0] adr;
  logic [`UART_DATA_WIDTH-1:0] dat_i, dat_o;
  logic [3:0]                  sel;
  logic                        we, stb, cyc, ack, irq;
  logic                        stx, srx, rts, dtr, cts, dsr, ri, dcd;

  uart_top dut (
    .wb_clk_i  (clk),
    .wb_rst_i  (rst),
    .wb_adr_i  (adr),
    .wb_dat_i  (dat_i),
    .wb_dat_o  (dat_o),
    .wb_we_i   (we),
    .wb_stb_i  (stb),
    .wb_cyc_i  (cyc),
    .wb_ack_o  (ack),
    .wb_sel_i  (sel),
    .int_o     (irq),
    .stx_pad_o (stx),
    .srx_pad_i (srx),
    .rts_pad_o (rts),
    .cts_pad_i (cts),
    .dtr_pad_o (dtr),
    .dsr_pad_i (dsr),
    .ri_pad_i  (ri),
    .dcd_pad_i (dcd)
  );

  // Mismos bind que tb/tb_top.sv
  bind uart_top uart_wb_sva u_wb_sva (
    .wb_clk_i  (wb_clk_i),
    .wb_rst_i  (wb_rst_i),
    .wb_adr_i  (wb_adr_i),
    .wb_dat_i  (wb_dat_i),
    .wb_dat_o  (wb_dat_o),
    .wb_sel_i  (wb_sel_i),
    .wb_we_i   (wb_we_i),
    .wb_stb_i  (wb_stb_i),
    .wb_cyc_i  (wb_cyc_i),
    .wb_ack_o  (wb_ack_o),
    .lcr       (lcr),
    .rf_count  (rf_count)
  );

  bind uart_top uart_ser_sva u_ser_sva (
    .wb_clk_i    (wb_clk_i),
    .wb_rst_i    (wb_rst_i),
    .stx_pad_o   (stx_pad_o),
    .srx_pad_i   (srx_pad_i),
    .rts_pad_o   (rts_pad_o),
    .dtr_pad_o   (dtr_pad_o),
    .cts_pad_i   (cts_pad_i),
    .dsr_pad_i   (dsr_pad_i),
    .ri_pad_i    (ri_pad_i),
    .dcd_pad_i   (dcd_pad_i),
    .int_o       (int_o),
    .lcr         (lcr),
    .mcr         (mcr),
    .dl          (regs.dl),
    .iir         (iir),
    .msr         (msr),
    .tstate      (tstate),
    .tf_count    (tf_count),
    .start_dlc   (regs.start_dlc),
    .rda_int_pnd (regs.rda_int_pnd),
    .rda_int     (regs.rda_int)
  );

  // Helpers Wishbone 32-bit big-endian
  task automatic wb_wr(input logic [4:0] a, input logic [7:0] d,
                       input logic [3:0] s_ovr = 4'b0, input bit use_ovr = 1'b0);
    logic [3:0]  s;
    logic [31:0] wdat;
    s    = use_ovr ? s_ovr : (4'b1000 >> a[1:0]);
    wdat = {4{d}};
    @(posedge clk);
    adr   <= a;
    dat_i <= wdat;
    sel   <= s;
    we    <= 1'b1;
    cyc   <= 1'b1;
    stb   <= 1'b1;
    do @(posedge clk); while (!ack);
    cyc   <= 1'b0;
    stb   <= 1'b0;
    we    <= 1'b0;
  endtask

  task automatic wb_rd(input logic [4:0] a, output logic [31:0] d,
                       input logic [3:0] s_ovr = 4'b0, input bit use_ovr = 1'b0);
    logic [3:0] s;
    s = use_ovr ? s_ovr : (4'b1000 >> a[1:0]);
    @(posedge clk);
    adr <= a;
    sel <= s;
    we  <= 1'b0;
    cyc <= 1'b1;
    stb <= 1'b1;
    do @(posedge clk); while (!ack);
    d = dat_o;
    cyc <= 1'b0;
    stb <= 1'b0;
  endtask

  task automatic do_rst(input int cycles = 3);
    rst <= 1'b1;
    cyc <= 1'b0; stb <= 1'b0; we <= 1'b0;
    repeat (cycles) @(posedge clk);
    rst <= 1'b0;
    repeat (2) @(posedge clk);
  endtask

  logic [31:0] rdat;
  int unsigned f_before;

  task automatic check_viol(input string name, input int unsigned cnt_after);
    if (cnt_after > f_before)
      $display("[SMOKE_OK]   %s detecto violacion (n_fail: %0d -> %0d)", name, f_before, cnt_after);
    else
      $display("[SMOKE_ERR]  %s NO detecto violacion!", name);
  endtask

  initial begin
    rst = 1'b1; adr = '0; dat_i = '0; sel = 4'b1000;
    we = 1'b0; stb = 1'b0; cyc = 1'b0;
    srx = 1'b1; cts = 1'b1; dsr = 1'b1; ri = 1'b1; dcd = 1'b1;

    do_rst(4);

    // =========================================================================
    // FASE 1: COVERS LIMPIOS (solo debe subir n_dut_bug por AMB-03)
    // =========================================================================
    $display("\n=== FASE 1: DISPARANDO COVERS ===");

    // A-WB-04 (lectura RBR con FIFO vacía) y A-WB-05 (sel inválidos: 0000, 2 bits, 1111 en dir < 2)
    wb_rd(5'd0, rdat);
    wb_rd(5'd7, rdat, 4'b0000, 1'b1);
    wb_rd(5'd7, rdat, 4'b0011, 1'b1);
    wb_rd(5'd7, rdat, 4'b1111, 1'b1);

    // A-SER-01 con DL = 0 y datos en FIFO TX
    wb_wr(5'd0, 8'h55);
    repeat (12) @(posedge clk);

    // A-SER-02 con DL = 1 + A-INT-01 (subida/bajada de int_o con THRE)
    wb_wr(5'd1, 8'h02); // IER[1] = THRE enable
    wb_wr(5'd3, 8'h83); // DLAB = 1
    wb_wr(5'd1, 8'h00); // DLM = 0
    wb_wr(5'd0, 8'h01); // DLL = 1
    wb_wr(5'd3, 8'h03); // DLAB = 0, 8N1
    wb_wr(5'd0, 8'h55); // TX
    repeat (220) @(posedge clk);
    wb_rd(5'd2, rdat);  // leer IIR limpia THRE (baja int_o)
    repeat (5) @(posedge clk);

    // A-SER-02 con DL > 16 (DL = 20)
    wb_wr(5'd3, 8'h83);
    wb_wr(5'd0, 8'd20);
    wb_wr(5'd3, 8'h03);
    wb_wr(5'd0, 8'h55);
    repeat (3600) @(posedge clk);

    // A-SER-03 (loopback con carácter en curso) + A-MDM-01 / A-MDM-02
    wb_wr(5'd3, 8'h83);
    wb_wr(5'd0, 8'h01); // volver a DL = 1
    wb_wr(5'd3, 8'h03);
    wb_wr(5'd4, 8'h1F); // MCR: loopback=1, OUT2=1, OUT1=1, RTS=1, DTR=1
    wb_wr(5'd0, 8'hA5);
    repeat (40) @(posedge clk);
    wb_wr(5'd4, 8'h00); // salir de loopback
    repeat (5) @(posedge clk);

    // A-SER-04 (break a mitad de carácter)
    wb_wr(5'd0, 8'hAA);
    repeat (30) @(posedge clk);
    wb_wr(5'd3, 8'h43); // LCR[6] = 1 (break)
    repeat (20) @(posedge clk);
    wb_wr(5'd3, 8'h03); // quitar break

    // A-RST-01 (reset con tráfico activo)
    wb_wr(5'd0, 8'h3C);
    repeat (20) @(posedge clk);
    do_rst(3);

    $display("Fin Fase 1 -> wb_n_fail=%0d, ser_n_fail=%0d, ser_n_dut_bug=%0d",
             dut.u_wb_sva.n_fail, dut.u_ser_sva.n_fail, dut.u_ser_sva.n_dut_bug);

    // =========================================================================
    // FASE 2: VIOLACIONES CONTROLADAS (force / release)
    // =========================================================================
    $display("\n=== FASE 2: FORZANDO VIOLACIONES CONTROLADAS ===");

    // 1) A-WB-01: cambiar adr mientras cyc & stb & !ack
    f_before = dut.u_wb_sva.n_fail;
    @(posedge clk);
    adr <= 5'd7; sel <= 4'b0001; we <= 1'b0; cyc <= 1'b1; stb <= 1'b1;
    @(posedge clk);
    adr <= 5'd3;
    do @(posedge clk); while (!ack);
    cyc <= 1'b0; stb <= 1'b0;
    @(posedge clk);
    check_viol("A-WB-01", dut.u_wb_sva.n_fail);

    // 2) A-WB-02: retener ack en 0 más de ACK_MAX ciclos
    f_before = dut.u_wb_sva.n_fail;
    force dut.wb_ack_o = 1'b0;
    @(posedge clk);
    adr <= 5'd7; sel <= 4'b0001; we <= 1'b0; cyc <= 1'b1; stb <= 1'b1;
    repeat (6) @(posedge clk);
    release dut.wb_ack_o;
    cyc <= 1'b0; stb <= 1'b0;
    repeat (2) @(posedge clk);
    check_viol("A-WB-02", dut.u_wb_sva.n_fail);

    // 3) A-WB-03: forzar ack=1 sin cyc/stb
    f_before = dut.u_wb_sva.n_fail;
    force dut.wb_ack_o = 1'b1;
    repeat (2) @(posedge clk);
    release dut.wb_ack_o;
    @(posedge clk);
    check_viol("A-WB-03", dut.u_wb_sva.n_fail);

    // 4) A-WB-04: forzar X en wb_ack_o
    f_before = dut.u_wb_sva.n_fail;
    force dut.wb_ack_o = 1'bx;
    @(posedge clk);
    release dut.wb_ack_o;
    @(posedge clk);
    check_viol("A-WB-04", dut.u_wb_sva.n_fail);

    // 5) A-WB-05: sel inválido sin ack
    f_before = dut.u_wb_sva.n_fail;
    force dut.wb_ack_o = 1'b0;
    @(posedge clk);
    adr <= 5'd7; sel <= 4'b0011; we <= 1'b0; cyc <= 1'b1; stb <= 1'b1;
    repeat (6) @(posedge clk);
    release dut.wb_ack_o;
    cyc <= 1'b0; stb <= 1'b0;
    repeat (2) @(posedge clk);
    check_viol("A-WB-05", dut.u_wb_sva.n_fail);

    // 6) A-SER-01: forzar stx=0 en reposo con LCR[6]=0
    f_before = dut.u_ser_sva.n_fail;
    force dut.stx_pad_o = 1'b0;
    repeat (2) @(posedge clk);
    release dut.stx_pad_o;
    @(posedge clk);
    check_viol("A-SER-01", dut.u_ser_sva.n_fail);

    // 7) A-SER-02: pulso corto en stx (3 ciclos con DL=1, menor a 16)
    wb_wr(5'd3, 8'h83); wb_wr(5'd0, 8'h01); wb_wr(5'd3, 8'h03); // DL = 1
    f_before = dut.u_ser_sva.n_fail;
    force dut.stx_pad_o = 1'b0;
    repeat (3) @(posedge clk);
    release dut.stx_pad_o;
    repeat (2) @(posedge clk);
    check_viol("A-SER-02", dut.u_ser_sva.n_fail);

    // 8) A-SER-03: forzar stx=0 en loopback
    wb_wr(5'd4, 8'h10);
    f_before = dut.u_ser_sva.n_fail;
    force dut.stx_pad_o = 1'b0;
    repeat (2) @(posedge clk);
    release dut.stx_pad_o;
    wb_wr(5'd4, 8'h00);
    check_viol("A-SER-03", dut.u_ser_sva.n_fail);

    // 9) A-SER-04: forzar stx=1 con break activo
    wb_wr(5'd3, 8'h43);
    f_before = dut.u_ser_sva.n_fail;
    force dut.stx_pad_o = 1'b1;
    repeat (2) @(posedge clk);
    release dut.stx_pad_o;
    wb_wr(5'd3, 8'h03);
    check_viol("A-SER-04", dut.u_ser_sva.n_fail);

    // 10) A-RST-01: forzar int_o=1 justo después de reset
    f_before = dut.u_ser_sva.n_fail;
    force dut.int_o = 1'b1;
    do_rst(2);
    release dut.int_o;
    check_viol("A-RST-01", dut.u_ser_sva.n_fail);

    // 11) A-INT-01: forzar int_o=1 con IIR[0]=1 durante > 2 ciclos
    f_before = dut.u_ser_sva.n_fail;
    force dut.int_o = 1'b1;
    repeat (5) @(posedge clk);
    release dut.int_o;
    check_viol("A-INT-01", dut.u_ser_sva.n_fail);

    // 12) A-MDM-02: forzar MSR[7:4] distinto de MCR en loopback
    wb_wr(5'd4, 8'h1F);
    @(posedge clk);
    f_before = dut.u_ser_sva.n_fail;
    force dut.msr = 8'h00;
    repeat (2) @(posedge clk);
    release dut.msr;
    wb_wr(5'd4, 8'h00);
    check_viol("A-MDM-02", dut.u_ser_sva.n_fail);

    // Nota: A-MDM-01 ya reporta AMB-03 (n_dut_bug > 0) en Fase 1
    $display("Resumen A-MDM-01 (AMB-03): n_dut_bug = %0d", dut.u_ser_sva.n_dut_bug);
    $display("\n=== FIN PRUEBA DE HUMO SVA ===");
    $finish;
  end

endmodule : tb_sva_smoke