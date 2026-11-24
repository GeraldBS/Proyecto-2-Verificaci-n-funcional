class uart_line_cfg extends uvm_object;
  `uvm_object_utils(uart_line_cfg)

  // configuración (aleatoria)
  rand bit [1:0]  wls;          // 0...3 = 5...8 bits
  rand bit        stb;          // 0: 1 bit de parada, 1: 1.5 (5 bits) o 2
  rand uart_par_e par_mode;     // uniforme entre los 5 modos
  rand bit        eps_dc, sp_dc;  // valor de EPS/SP cuando no hay paridad
  rand bit [15:0] dl;
  rand bit        dl_fast;      // 1: banda de 1 a 16, 0: banda de 17 a dl_max
  rand bit        dl_lsb_first; // escribir DLL antes que DLM

  // knobs
  int          lcr_wls = -1;    // -1 la sortea, 0 a 3 la fija
  int unsigned dl_min  = 1;
  int unsigned dl_max  = 255;
  int          fmt     = -1;    // solo lo usa uart_frame_sweep_test, formato 0 a 39

  constraint c_wls { if (lcr_wls >= 0) wls == lcr_wls; }

  // fmt = wls + 4*stb + 8*paridad, asi los 40 formatos quedan numerados
  constraint c_fmt {
    if (fmt >= 0) {
      wls == fmt % 4;
      stb == (fmt / 4) % 2;
      int'(par_mode) == fmt / 8;
    }
  }

  // 85 % en la banda rapida y 15 % en la lenta, si una banda queda fuera
  // de [dl_min:dl_max] todos caen en la otra
  constraint c_dl {
    dl inside {[dl_min : dl_max]};
    dl_fast dist { 1 := 85, 0 := 15 };
    if (dl_min > 16)  dl_fast == 0;
    if (dl_max <= 16) dl_fast == 1;
    dl_fast -> dl <= 16;
    !dl_fast -> dl >= 17;
    solve dl_fast before dl;
  }

  // con DL >= 256 el DLM ya no es 0 y el orden si cambia el divisor intermedio
  constraint c_order {
    if (dl >= 256) dl_lsb_first dist { 1 := 50, 0 := 50 };
    else           dl_lsb_first dist { 1 := 10, 0 := 90 };
    solve dl before dl_lsb_first;
  }

  function new(string name = "uart_line_cfg");
    super.new(name);
  endfunction

  // valores derivados
  function bit pen();  return par_mode != PAR_NONE; endfunction
  function bit eps();  return (par_mode == PAR_NONE) ? eps_dc : (par_mode inside {PAR_EVEN, PAR_STICK0}); endfunction
  function bit sp();   return (par_mode == PAR_NONE) ? sp_dc  : (par_mode inside {PAR_STICK1, PAR_STICK0}); endfunction

  // byte de LCR, dlab y bc los decide quien escribe
  function bit [7:0] lcr(bit dlab = 0, bit bc = 0);
    return {dlab, bc, sp(), eps(), pen(), stb, wls};
  endfunction

  function int unsigned data_bits(); return 5 + wls; endfunction

  // bits de parada en dieciseisavos de bit (16, 24 o 32)
  function int unsigned stop_ticks();
    if (!stb) return 16;
    return (wls == 0) ? 24 : 32;
  endfunction

  // ciclos de reloj de un bit, con DL = 0 usamos DL = 1 como respaldo
  function int unsigned bit_cycles();
    return 16 * ((dl == 0) ? 1 : dl);
  endfunction

  // Tc, ciclos de un carácter completo (inicio + datos + paridad + parada)
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
