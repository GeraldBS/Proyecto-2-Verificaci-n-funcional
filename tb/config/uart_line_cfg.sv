//////////////////////////////////////////////////////////////////////
// uart_line_cfg: 
// Formato de la línea (LCR) y divisor (DL)
//////////////////////////////////////////////////////////////////////

class uart_line_cfg extends uvm_object;
  `uvm_object_utils(uart_line_cfg) // PAra crear objetos de factory

  // configuración (aleatoria)
  rand bit [1:0]  wls;          
  rand bit        stb;          
  rand uart_par_e par_mode;     
  rand bit        eps_dc, sp_dc;  
  rand bit [15:0] dl;
  rand bit        dl_fast;      
  rand bit        dl_lsb_first; 

  // knobs
  int          lcr_wls = -1;    // -1 la sortea, 0 a 3 la fija
  int unsigned dl_min  = 1;
  int unsigned dl_max  = 255;
  int          fmt     = -1;    // solo lo usa uart_frame_sweep_test: formato 0 a 39 (si se usa, gana sobre lcr_wls)

  constraint c_wls { if (lcr_wls >= 0 && fmt < 0) wls == lcr_wls; }

  constraint c_fmt { if (fmt >= 0) { fmt < 40; wls == fmt % 4; stb == (fmt / 4) % 2; par_mode == uart_par_e'(fmt / 8); }}

  // 85 % en la banda rápida y 15 % en la lenta
  constraint c_dl {dl inside {[dl_min : dl_max]}; dl_fast dist { 1 := 85, 0 := 15 }; if (dl_min > 16)  dl_fast == 0; if (dl_max <= 16) dl_fast == 1; dl_fast -> dl <= 16; !dl_fast -> dl >= 17; solve dl_fast before dl; }

  // con DL >= 256 el DLM ya no es 0 y el orden sí cambia el divisor intermedio
  constraint c_order { if (dl >= 256) dl_lsb_first dist { 1 := 50, 0 := 50 }; else dl_lsb_first dist { 1 := 10, 0 := 90 }; solve dl before dl_lsb_first; }

  function new(string name = "uart_line_cfg"); // constructor
    super.new(name);
  endfunction

  // valores derivados
  function bit pen();  
    return par_mode != PAR_NONE; 
  endfunction

  function bit eps();  
    return (par_mode == PAR_NONE) ? eps_dc : (par_mode inside {PAR_EVEN, PAR_STICK0}); 
  endfunction

  function bit sp();   
    return (par_mode == PAR_NONE) ? sp_dc  : (par_mode inside {PAR_STICK1, PAR_STICK0}); 
  endfunction

  // byte de LCR, dlab y bc 
  function bit [7:0] lcr(bit dlab = 0, bit bc = 0); // Todos los bits comienzan en 0
    bit [7:0] v = '0;
    v[UART_LCR_WLS +: 2] = wls;        // bits [1:0]: longitud del carácter
    v[UART_LCR_STB] = stb;             // bit 2: bits de parada
    v[UART_LCR_PEN] = pen();           // bit 3: hay paridad
    v[UART_LCR_EPS] = eps();           // bit 4: paridad par
    v[UART_LCR_SP] = sp();             // bit 5: paridad fija
    v[UART_LCR_BRK] = bc;              // bit 6: break
    v[UART_LCR_DLAB] = dlab;           // bit 7: acceso al divisor
    return v;
  endfunction

  function int unsigned data_bits(); 
    return 5 + wls; 
  endfunction

  function int unsigned stop_ticks();
    if (!stb) return 16;
    return (wls == 0) ? 24 : 32;
  endfunction

  // ciclos de reloj de un bit
  function int unsigned bit_cycles();
    return 16 * ((dl == 0) ? 1 : dl);
  endfunction

  // Ciclos de un carácter completo (inicio + datos + paridad + parada)
  function longint unsigned tc_cycles();
    longint unsigned ticks = 16 * (1 + data_bits() + pen()) + stop_ticks();
    return ticks * ((dl == 0) ? 1 : dl);
  endfunction

  // N ninguna, O impar, E par, S stick 1, D stick 0
  function string par_char();
    case (par_mode)
      PAR_NONE:   return "N";
      PAR_ODD:    return "O";
      PAR_EVEN:   return "E";
      PAR_STICK1: return "S";
      default:    return "D";
    endcase
  endfunction

  // imprime texto que describe el formato vigente
  function string convert2string();
    return $sformatf("%0d%s%s DL=%0d%s", data_bits(), par_char(),
                     stb ? ((wls == 0) ? "1.5" : "2") : "1", dl,
                     dl_lsb_first ? " (DLL primero)" : "");
  endfunction
endclass : uart_line_cfg
