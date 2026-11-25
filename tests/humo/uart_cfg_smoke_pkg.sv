//////////////////////////////////////////////////////////////////////////////////
// uart_cfg_smoke_pkg.sv
// Prueba de humo de los objetos de configuración (fases F1 y F2), sin agentes
// ni DUT, solo para ver si uart_types, uart_line_cfg, uart_ctrl_cfg y uart_env_cfg funcionan
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

package uart_cfg_smoke_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import uart_pkg::*;   // clases del ambiente y constantes UART_* de uart_types.sv

  // Compara un valor con el esperado
  function automatic void cfg_check(string what, longint got, longint exp);
    if (got !== exp)
      `uvm_error("SMOKE", $sformatf("%s: obtuvo 0x%0h, esperaba 0x%0h", what, got, exp))
    else
      `uvm_info("SMOKE", $sformatf("%s = 0x%0h OK", what, got), UVM_LOW)
  endfunction

  // Revisa que un valor esté dentro de un rango
  function automatic void cfg_range(string what, longint got, longint lo, longint hi);
    if (got < lo || got > hi)
      `uvm_error("SMOKE", $sformatf("%s: %0d fuera de [%0d:%0d]", what, got, lo, hi))
    else
      `uvm_info("SMOKE", $sformatf("%s = %0d OK (rango %0d a %0d)", what, got, lo, hi), UVM_LOW)
  endfunction

  class uart_cfg_smoke_test extends uvm_test;
    `uvm_component_utils(uart_cfg_smoke_test)   // macro de UVM: registra la clase en la factory

    uart_env_cfg cfg;   // configuración de la corrida (con los plusargs de la línea de comandos)

    // Constructor
    function new(string name = "uart_cfg_smoke_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    // F2: crea la configuración y lee los plusargs; uno fuera de rango termina aquí con UVM_FATAL
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      cfg = uart_env_cfg::type_id::create("cfg");   // crea el objeto con la factory
      cfg.parse_plusargs();
      cfg.print_knobs();
    endfunction

    // F1 y F2 en orden
    task run_phase(uvm_phase phase);
      phase.raise_objection(this);   // mantiene la prueba viva
      check_formulas();   // F1: tiempos y bytes de registro con valores a mano
      check_sorteo();     // F1: 1000 objetos de línea y de control
      check_formatos();   // F1: los 40 formatos con fmt (lo que usa CE-05)
      check_plusargs();   // F2: valor y origen de los knobs
      phase.drop_objection(this);   // termina la prueba
    endtask

    // F1: bit_cycles(), tc_cycles(), lcr(), fcr(), mcr() e ier_byte() con valores conocidos
    function void check_formulas();
      uart_line_cfg l = uart_line_cfg::type_id::create("l");
      uart_ctrl_cfg c = uart_ctrl_cfg::type_id::create("c");

      // 8N1 con DL = 1: 16 ciclos por bit y 10 bits por carácter
      l.wls = 3;  l.stb = 0;  l.par_mode = PAR_NONE;  l.eps_dc = 0;  l.sp_dc = 0;  l.dl = 1;
      cfg_check("bit_cycles 8N1 DL=1", l.bit_cycles(), 16);
      cfg_check("tc_cycles 8N1 DL=1",  l.tc_cycles(),  160);
      cfg_check("lcr 8N1",             l.lcr(),        8'h03);
      cfg_check("lcr 8N1 con DLAB",    l.lcr(1),       8'h83);
      cfg_check("lcr 8N1 con break",   l.lcr(0, 1),    8'h43);

      // 8E2 con DL = 3: (1 + 8 + 1) bits y 2 de parada, a 3 veces el tiempo
      l.stb = 1;  l.par_mode = PAR_EVEN;  l.dl = 3;
      cfg_check("bit_cycles DL=3",     l.bit_cycles(), 48);
      cfg_check("tc_cycles 8E2 DL=3",  l.tc_cycles(),  576);

      // 5N1.5 con DL = 1: con 5 bits, LCR[2] = 1 da 1.5 de parada
      l.wls = 0;  l.par_mode = PAR_NONE;  l.dl = 1;
      cfg_check("tc_cycles 5N1.5 DL=1", l.tc_cycles(), 120);

      // DL = 0 usa DL = 1 como respaldo
      l.wls = 3;  l.stb = 0;  l.dl = 0;
      cfg_check("bit_cycles DL=0",     l.bit_cycles(), 16);

      // los 4 modos con paridad (8 bits, 1 parada)
      l.stb = 0;  l.dl = 1;
      l.par_mode = PAR_ODD;     cfg_check("lcr 8O1", l.lcr(), 8'h0B);
      l.par_mode = PAR_EVEN;    cfg_check("lcr 8E1", l.lcr(), 8'h1B);
      l.par_mode = PAR_STICK1;  cfg_check("lcr 8M1", l.lcr(), 8'h2B);
      l.par_mode = PAR_STICK0;  cfg_check("lcr 8S1", l.lcr(), 8'h3B);

      // FIFO: nivel de disparo y byte de FCR
      c.tl = 2;  c.rx_clr = 1;  c.tx_clr = 0;  c.fcr_dc = 4'h0;
      cfg_check("trigger_level tl=2", c.trigger_level(), 8);
      cfg_check("fcr tl=2 rx_clr",    c.fcr(),           8'h82);
      c.tl = 3;  c.rx_clr = 0;  c.tx_clr = 1;
      cfg_check("trigger_level tl=3", c.trigger_level(), 14);
      cfg_check("fcr tl=3 tx_clr",    c.fcr(),           8'hC4);
      c.tl = 0;  c.tx_clr = 0;  c.fcr_dc = 4'hF;
      cfg_check("fcr con bits ignorados", c.fcr(),       8'h39);

      // IER y MCR
      c.ier = 4'hA;  c.ier_dc = 4'h5;
      cfg_check("ier_byte", c.ier_byte(), 8'h5A);
      c.dtr = 1;  c.rts = 0;  c.out1 = 0;  c.out2 = 1;  c.loop = 0;  c.mcr_dc = 3'h0;
      cfg_check("mcr dtr y out2", c.mcr(), 8'h09);
      c.dtr = 0;  c.out2 = 0;  c.loop = 1;  c.mcr_dc = 3'h7;
      cfg_check("mcr loop y bits reservados", c.mcr(), 8'hF0);
    endfunction

    // F1: 1000 sorteos con los valores por defecto (no dependen de los plusargs)
    function void check_sorteo();
      uart_line_cfg l = uart_line_cfg::type_id::create("l");
      uart_ctrl_cfg c = uart_ctrl_cfg::type_id::create("c");
      bit          fmt_visto[40];   // formatos que salieron
      bit          tl_visto[4];     // niveles de disparo que salieron
      int unsigned fallos = 0, formatos = 0, niveles = 0;
      int unsigned rapida = 0, dll_primero = 0, loopback = 0, dl_fuera = 0;

      repeat (1000) begin
        if (!l.randomize()) fallos++;
        if (!c.randomize()) fallos++;
        fmt_visto[l.wls + 4*l.stb + 8*int'(l.par_mode)] = 1;
        tl_visto[c.tl] = 1;
        if (l.dl <= 16)                        rapida++;
        if (l.dl_lsb_first)                    dll_primero++;
        if (c.loop)                            loopback++;
        if (l.dl < l.dl_min || l.dl > l.dl_max) dl_fuera++;
      end
      foreach (fmt_visto[i]) formatos += fmt_visto[i];
      foreach (tl_visto[i])  niveles  += tl_visto[i];

      cfg_check("randomize() fallidos",         fallos,   0);
      cfg_check("formatos distintos (de 40)",   formatos, 40);
      cfg_check("niveles de disparo (de 4)",    niveles,  4);
      cfg_check("DL fuera de [dl_min:dl_max]",  dl_fuera, 0);
      cfg_range("DL de 1 a 16 (de 1000)",       rapida,      800, 900);   // 85 %
      cfg_range("DLL primero (de 1000)",        dll_primero,  60, 140);   // 10 %
      cfg_range("loopback (de 1000)",           loopback,    140, 260);   // 20 %
    endfunction

    // F1: con fmt de 0 a 39 el formato queda fijo (wls + 4*stb + 8*paridad)
    function void check_formatos();
      uart_line_cfg l = uart_line_cfg::type_id::create("l");
      int unsigned  malos = 0;

      for (int f = 0; f < 40; f++) begin
        l.fmt = f;
        if (!l.randomize() || l.wls != f % 4 || l.stb != (f / 4) % 2 || int'(l.par_mode) != f / 8)
          malos++;
      end
      l.fmt = -1;
      cfg_check("formatos mal fijados con fmt", malos, 0);

      // lcr_wls fija la longitud en todos los sorteos
      l.lcr_wls = 2;
      malos = 0;
      repeat (100) if (!l.randomize() || l.wls != 2) malos++;
      cfg_check("lcr_wls = 2 no respetado", malos, 0);
    endfunction

    // Fila de la tabla de knobs de un plusarg ("" si no está)
    function string fila_de(string name);
      foreach (cfg.knob_rows[i])
        if (cfg.knob_rows[i].substr(3, 2 + name.len()) == name &&
            cfg.knob_rows[i][3 + name.len()] == " ")
          return cfg.knob_rows[i];
      return "";
    endfunction

    // F2: +UART_DL_MAX cambia el knob y la tabla marca su origen (corre con y sin el plusarg)
    function void check_plusargs();
      int unsigned v;
      bit          hay  = $value$plusargs("UART_DL_MAX=%d", v);
      string       fila = fila_de("UART_DL_MAX");
      string       origen;
      int unsigned fuera = 0;

      cfg_check("filas de la tabla de knobs (27 plusargs)", cfg.knob_rows.size(), 27);

      origen = fila.substr(fila.len() - 7, fila.len() - 1);
      if (hay) begin
        cfg_check("dl_max con +UART_DL_MAX", cfg.line.dl_max, v);
        if (origen != "plusarg") `uvm_error("SMOKE", $sformatf("la fila dice '%s' y debía decir plusarg", origen))
      end else begin
        cfg_check("dl_max por defecto", cfg.line.dl_max, 255);
        if (origen != "defecto") `uvm_error("SMOKE", $sformatf("la fila dice '%s' y debía decir defecto", origen))
      end

      // los sorteos respetan el límite vigente
      repeat (200) begin
        if (!cfg.line.randomize()) `uvm_error("SMOKE", "randomize() falló con los knobs de la corrida")
        if (cfg.line.dl < cfg.line.dl_min || cfg.line.dl > cfg.line.dl_max) fuera++;
      end
      cfg_check("DL fuera de rango con los knobs de la corrida", fuera, 0);
    endfunction

    // Resultado final
    function void report_phase(uvm_phase phase);
      uvm_report_server srv = uvm_report_server::get_server();
      if (srv.get_severity_count(UVM_ERROR) == 0 && srv.get_severity_count(UVM_FATAL) == 0)
        `uvm_info("SMOKE", "RESULTADO: PASA", UVM_NONE)
      else
        `uvm_info("SMOKE", "RESULTADO: FALLA", UVM_NONE)
    endfunction
  endclass : uart_cfg_smoke_test

endpackage : uart_cfg_smoke_pkg
