//////////////////////////////////////////////////////////////////////
// uart_base_vseq: base de todas las secuencias virtuales           //
//////////////////////////////////////////////////////////////////////
// Tiene lo que todas usan: acceso a la configuración por p_sequencer,
// lecturas y escrituras Wishbone de un registro, esperas medidas en
// ciclos o en tiempos de carácter (Tc) y sorteos con los knobs.
//////////////////////////////////////////////////////////////////////
class uart_base_vseq extends uvm_sequence;
  `uvm_object_utils(uart_base_vseq)
  `uvm_declare_p_sequencer(uart_virtual_sequencer)

  function new(string name = "uart_base_vseq");
    super.new(name);
  endfunction

  // atajos
  function uart_env_cfg  cfg();  return p_sequencer.cfg;      endfunction
  function uart_line_cfg line(); return p_sequencer.cfg.line; endfunction
  function uart_ctrl_cfg ctrl(); return p_sequencer.cfg.ctrl; endfunction

  // ---------------------------------------------------------- sorteos
  // true con probabilidad pct/100
  function bit pct(int unsigned p);
    return $urandom_range(99) < p;
  endfunction

  // índice al azar según una lista de pesos (los knobs *_W)
  function int unsigned pick_w(int unsigned weights[]);
    int unsigned total = 0, draw;
    foreach (weights[i]) total += weights[i];
    draw = $urandom_range(total - 1);
    foreach (weights[i]) begin
      if (draw < weights[i]) return i;
      draw -= weights[i];
    end
    return 0;
  endfunction

  // dato con el knob de esquinas (00, FF, 55, AA)
  function bit [7:0] pick_data();
    bit [7:0] corners[4] = '{8'h00, 8'hFF, 8'h55, 8'hAA};
    if (pct(cfg().data_corner_pct)) return corners[$urandom_range(3)];
    return $urandom_range(255);
  endfunction

  // valor en una de tres bandas [a0:b0], [a1:b1], [a2:b2] recortadas a
  // [lo:hi]; una banda que queda vacía no se puede elegir
  function int unsigned pick_band3(int unsigned weights[], int unsigned band_lo[3], int unsigned band_hi[3],
                                   int unsigned lo, int unsigned hi);
    int unsigned usable[] = new[3];   // pesos, con 0 en las bandas que quedan vacías
    int unsigned band, low, high;
    foreach (usable[i]) begin
      low  = (band_lo[i] > lo) ? band_lo[i] : lo;
      high = (band_hi[i] < hi) ? band_hi[i] : hi;
      usable[i] = (low <= high) ? weights[i] : 0;
    end
    if (usable[0] + usable[1] + usable[2] == 0) return lo;
    band = pick_w(usable);
    low  = (band_lo[band] > lo) ? band_lo[band] : lo;
    high = (band_hi[band] < hi) ? band_hi[band] : hi;
    return $urandom_range(high, low);
  endfunction

  // ---------------------------------------------------------- esperas
  task wait_cycles(longint unsigned n);
    if (n == 0) return;
    // esperas largas con # para no iterar millones de flancos
    if (n > 64) #((n - 1) * UART_CLK_NS * 1ns);
    @(posedge p_sequencer.cfg.wb.vif.clk);
  endtask

  task wait_tc(longint unsigned n);
    wait_cycles(n * line().tc_cycles());
  endtask

  // ---------------------------------------------------------- bus
  task lock();   p_sequencer.bus_sem.get(1); endtask
  task unlock(); p_sequencer.bus_sem.put(1); endtask

  // Un acceso Wishbone; con held = 1 la llamada ya tiene el candado.
  // set_reg_access (de wb_item) pone el sel y el carril según adr. Con
  // bad_sel_ok = 1 el driver puede cambiar el sel por uno inválido
  // (AMB-05); solo lo pedimos donde eso no toca MCR ni el divisor.
  // rdata vuelve con el byte en [7:0], o la palabra completa en Debug.
  task wb_acc(bit we, bit [4:0] adr, bit [31:0] dat, output bit [31:0] rdata,
              input bit held = 0, bit bad_sel_ok = 0);
    wb_item item = wb_item::type_id::create("wb_item");
    if (!held) lock();
    start_item(item, -1, p_sequencer.wb_sqr);
    item.set_reg_access(adr, we, dat[7:0]);
    item.bad_sel_ok = bad_sel_ok;
    finish_item(item);
    // it.sel es el que usó el driver, por si lo cambió
    rdata = (adr >= 8) ? item.dat_rd : {24'h0, uart_lane8(item.sel, item.dat_rd)};
    if (!held) unlock();
  endtask

  task wb_write(bit [4:0] adr, bit [7:0] dat, bit held = 0);
    bit [31:0] dummy;
    wb_acc(1, adr, {24'h0, dat}, dummy, held);
  endtask

  task wb_read(bit [4:0] adr, output bit [7:0] dat, input bit held = 0);
    bit [31:0] word;
    wb_acc(0, adr, 32'h0, word, held);
    dat = word[7:0];
  endtask

  // escribe el divisor con DLAB = 1 en el orden pedido y deja LCR con
  // el formato vigente; held porque es una ventana con DLAB = 1
  task write_divisor(bit held = 0);
    if (!held) lock();
    wb_write(UART_LCR, line().lcr(1'b1), 1);
    if (line().dl_lsb_first) begin
      wb_write(UART_DLL, line().dl[7:0], 1);
      wb_write(UART_DLM, line().dl[15:8], 1);
    end else begin
      // lo que pide la spec: el contador arranca al escribir DLL
      wb_write(UART_DLM, line().dl[15:8], 1);
      wb_write(UART_DLL, line().dl[7:0], 1);
    end
    wb_write(UART_LCR, line().lcr(1'b0), 1);
    if (!held) unlock();
  endtask

  // ¿hay que dejar de generar tráfico?
  function bit stop_now();
    return p_sequencer.rst_hit;
  endfunction
endclass : uart_base_vseq
