//////////////////////////////////////////////////////////////////////
// uart_line_cfg: formato de la línea (LCR) y divisor (DL)          //
//////////////////////////////////////////////////////////////////////
// La secuencia principal lo aleatoriza al inicio de cada episodio.
// Los campos rand son la configuración del UART; los int unsigned
// son los knobs que mueven las probabilidades (los llena
// uart_env_cfg::parse_plusargs). Todos los agentes y el scoreboard
// tienen la misma referencia, así que siempre ven el formato vigente.
//////////////////////////////////////////////////////////////////////
class uart_line_cfg extends uvm_object;
  `uvm_object_utils(uart_line_cfg)

  // ---------------- configuración (aleatoria) ----------------
  rand bit [1:0]  wls;          // 0..3 = 5..8 bits
  rand bit        stb;          // 0: 1 bit de parada, 1: 1.5 (5 bits) o 2
  rand uart_par_e par_mode;
  rand bit        eps_dc, sp_dc;  // valor de EPS/SP cuando no hay paridad (no afectan la trama)
  rand bit [15:0] dl;
  rand int unsigned dl_band;    // 0: DL=0, 1: rápido, 2..4: bandas de la cola
  rand bit        dl_lsb_first; // escribir DLL antes que DLM (al revés de la spec)

  // ---------------- knobs ----------------
  int unsigned wls_w[]      = '{1, 1, 1, 1};
  int unsigned stb_w[]      = '{1, 1};
  int unsigned par_w[]      = '{1, 1, 1, 1, 1};
  int unsigned dl_zero_pct  = 1;
  int unsigned dl_max_fast  = 16;
  int unsigned dl_max       = 65535;
  int unsigned dl_tail_w[]  = '{30, 8, 2};   // por mil: 17-255, 256-4095, 4096-dl_max
  int unsigned dl_lsb_first_pct = 10;

  // límites y pesos de cada banda de DL; se calculan en pre_randomize
  // para que una banda vacía (por ejemplo si dl_max_fast > 255) tenga peso 0
  int unsigned band_lo[5], band_hi[5], band_w[5];

  constraint c_wls { wls dist { 0 := wls_w[0], 1 := wls_w[1], 2 := wls_w[2], 3 := wls_w[3] }; }
  constraint c_stb { stb dist { 0 := stb_w[0], 1 := stb_w[1] }; }
  constraint c_par {
    par_mode dist { PAR_NONE := par_w[0], PAR_ODD := par_w[1], PAR_EVEN := par_w[2],
                    PAR_STICK1 := par_w[3], PAR_STICK0 := par_w[4] };
  }
  constraint c_band {
    dl_band dist { 0 := band_w[0], 1 := band_w[1], 2 := band_w[2], 3 := band_w[3], 4 := band_w[4] };
  }
  constraint c_dl {
    foreach (band_lo[k]) (dl_band == k) -> dl inside {[band_lo[k] : band_hi[k]]};
    solve dl_band before dl;
  }
  constraint c_order { dl_lsb_first dist { 1 := dl_lsb_first_pct, 0 := 100 - dl_lsb_first_pct }; }

  function new(string name = "uart_line_cfg");
    super.new(name);
  endfunction

  function void pre_randomize();
    int unsigned tail_tot = dl_tail_w[0] + dl_tail_w[1] + dl_tail_w[2];
    int unsigned zero_pm  = 10 * dl_zero_pct;          // de % a por mil
    int unsigned top      = (dl_max < 1) ? 1 : dl_max;
    int unsigned fast     = (dl_max_fast > top) ? top : dl_max_fast;
    if (fast < 1) fast = 1;

    band_lo[0] = 0;                     band_hi[0] = 0;
    band_lo[1] = 1;                     band_hi[1] = fast;
    band_lo[2] = fast + 1;              band_hi[2] = (top < 255)  ? top : 255;
    band_lo[3] = (fast + 1 > 256)  ? fast + 1 : 256;   band_hi[3] = (top < 4095) ? top : 4095;
    band_lo[4] = (fast + 1 > 4096) ? fast + 1 : 4096;  band_hi[4] = top;

    band_w[0] = zero_pm;
    band_w[1] = (zero_pm + tail_tot >= 1000) ? 1 : 1000 - zero_pm - tail_tot;
    for (int k = 2; k <= 4; k++) begin
      band_w[k] = dl_tail_w[k-2];
      // banda vacía: peso 0 y rango válido para que el solver no se queje
      if (band_lo[k] > band_hi[k]) begin
        band_w[k]  = 0;
        band_lo[k] = band_hi[k];
      end
    end
  endfunction

  // ---------------- valores derivados ----------------
  function bit pen();  return par_mode != PAR_NONE; endfunction
  function bit eps();  return (par_mode == PAR_NONE) ? eps_dc : (par_mode inside {PAR_EVEN, PAR_STICK0}); endfunction
  function bit sp();   return (par_mode == PAR_NONE) ? sp_dc  : (par_mode inside {PAR_STICK1, PAR_STICK0}); endfunction

  // byte de LCR; dlab y bc los decide quien escribe
  function bit [7:0] lcr(bit dlab = 0, bit bc = 0);
    return {dlab, bc, sp(), eps(), pen(), stb, wls};
  endfunction

  function int unsigned data_bits(); return 5 + wls; endfunction

  // bits de parada en dieciseisavos de bit (16, 24 o 32)
  function int unsigned stop_ticks();
    if (!stb) return 16;
    return (wls == 0) ? 24 : 32;
  endfunction

  // ciclos de reloj de un bit; con DL = 0 usamos DL = 1 como respaldo
  function int unsigned bit_cycles();
    return 16 * ((dl == 0) ? 1 : dl);
  endfunction

  // Tc: ciclos de un carácter completo (inicio + datos + paridad + parada)
  function longint unsigned tc_cycles();
    longint unsigned ticks = 16 * (1 + data_bits() + pen()) + stop_ticks();
    return ticks * ((dl == 0) ? 1 : dl);
  endfunction

  function string convert2string();
    return $sformatf("%0d%s%s DL=%0d%s", data_bits(), par_mode.name(),
                     stb ? ((wls == 0) ? " 1.5stop" : " 2stop") : " 1stop", dl,
                     dl_lsb_first ? " (DLL primero)" : "");
  endfunction
endclass : uart_line_cfg
