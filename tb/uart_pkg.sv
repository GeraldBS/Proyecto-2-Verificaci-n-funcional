//////////////////////////////////////////////////////////////////////////////////
// uart_pkg.sv 
// Paquete del ambiente UVM del UART 16550.
//
// Contiene:
//   1. Constantes de uvm_config_db
//   2. uart_knobs
//   3. Objetos de configuración
//
// El objetivo es que sirva como base para fijar nombres, defaults y plusargs. 
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps   // unidad de tiempo 1 ns, precisión 1 ps
`include "uart_defines.v"   // anchos del bus (UART_ADDR_WIDTH y UART_DATA_WIDTH)

package uart_pkg;

  import uvm_pkg::*;   // clases y funciones de UVM
  `include "uvm_macros.svh"  //incluyendo macros

  // Tipos compartidos

  typedef enum int {PAR_NONE = 0, PAR_ODD, PAR_EVEN, PAR_STICK1, PAR_STICK0} par_mode_e;
  typedef enum int {SW_IRQ = 0, SW_POLL}                                       sw_mode_e;
  typedef enum int {DL_MSB_FIRST = 0, DL_LSB_FIRST}                            dl_order_e;
  typedef enum int {RXE_NONE = 0, RXE_PARITY, RXE_FRAME, RXE_BREAK,
                    RXE_GLITCH_REJ, RXE_GLITCH_START, RXE_BAUD_IN, RXE_BAUD_OUT} rx_err_e;
  typedef enum int {IIR_NONE = 0, IIR_RLS, IIR_RDA, IIR_TIMEOUT, IIR_THRE, IIR_MSI} iir_id_e;

  // uvm_config_db 
  // Interfaces virtuales

  localparam string UART_PATH_VIF  = "uvm_test_top*";   // ruta donde tb_top publica las interfaces
  localparam string UART_KEY_WB_VIF  = "wb_vif";    // nombre de la interfaz Wishbone
  localparam string UART_KEY_SER_VIF = "ser_vif";   // nombre de la interfaz serie
  localparam string UART_KEY_MDM_VIF = "mdm_vif";   // nombre de la interfaz de módem

  // Objetos de configuración

  localparam string UART_PATH_ENV     = "env*";          // uart_env_cfg
  localparam string UART_PATH_WB_AGT  = "env.wb_agt*";   // wb_agent_cfg
  localparam string UART_PATH_SER_AGT = "env.ser_agt*";  // uart_ser_agent_cfg
  localparam string UART_PATH_MDM_AGT = "env.mdm_agt*";  // modem_agent_cfg
  localparam string UART_PATH_SCB     = "env.scb*";      // uart_scb_cfg
  localparam string UART_PATH_COV     = "env.cov*";      // uart_cov_cfg


  // Nombre del campo con el que se publican todos los objetos de configuración
  localparam string UART_KEY_CFG = "cfg";

  // uart_knobs

  // Clase estática: lee los plusargs y guarda de dónde salió cada valor
  class uart_knobs;
    static string log_name[$];   // registro: nombre del knob
    static string log_val [$];   // registro: valor final
    static string log_src [$];   // registro: origen (default o plusarg)

    // Anota el nombre, valor y origen de un knob en el registro
    static function void record(string name, string val, bit from_plusarg);
      log_name.push_back(name);
      log_val .push_back(val);
      log_src .push_back(from_plusarg ? "plusarg" : "default");
    endfunction

    // Entero: lee +NOMBRE=valor; si no viene, deja el default
    static function void get_int(string name, ref int val);
      int tmp;
      if ($value$plusargs({name, "=%d"}, tmp)) begin
        val = tmp;
        record(name, $sformatf("%0d", val), 1);
      end
      else record(name, $sformatf("%0d", val), 0);
    endfunction

    // Lista de enteros: lee +NOMBRE=a,b,c; debe traer tantos valores como el arreglo
    static function void get_int_list(string name, ref int val[]);
      string s;
      string item;
      int    n;
      int    start;
      int    idx;
      int    parsed[$];
      string shown;

      if ($value$plusargs({name, "=%s"}, s)) begin
        start = 0;
        for (n = 0; n <= s.len(); n++) begin
          if (n == s.len() || s[n] == ",") begin
            item = s.substr(start, n - 1);
            parsed.push_back(item.atoi());
            start = n + 1;
          end
        end
        if (parsed.size() != val.size())   // la lista debe coincidir con el tamaño del arreglo
          `uvm_fatal("KNOBS", $sformatf("+%s espera %0d valores y recibió %0d (%s)",
                                         name, val.size(), parsed.size(), s))
        foreach (parsed[idx]) val[idx] = parsed[idx];
        record(name, s, 1);
      end
      else begin
        shown = "";
        foreach (val[idx]) shown = {shown, ((idx != 0) ? "," : ""), $sformatf("%0d", val[idx])};
        record(name, shown, 0);
      end
    endfunction

    // Cadena: lee +NOMBRE=texto; si no viene, deja el default
    static function void get_str(string name, ref string val);
      string tmp;
      if ($value$plusargs({name, "=%s"}, tmp)) begin
        val = tmp;
        record(name, val, 1);
      end
      else record(name, val, 0);
    endfunction

    // Imprime la tabla de knobs con su valor y origen (la llama uart_base_test)
    static function void print_knobs();
      string msg = "\n--- Knobs (nombre, valor, origen) ---\n";
      foreach (log_name[i])
        msg = {msg, $sformatf("  +%-28s = %-16s [%s]\n", log_name[i], log_val[i], log_src[i])};
      `uvm_info("KNOBS", msg, UVM_LOW)   // macro de UVM: imprime el mensaje
    endfunction
  endclass : uart_knobs

  // Objetos de configuración

  // Formato de línea: LCR (longitud, parada, paridad) y divisor DL
  class uart_line_cfg extends uvm_object;
    `uvm_object_utils(uart_line_cfg)   // macro de UVM: registra la clase en la factory

    // Pesos y parámetros por defecto (secciones 6.15 y 7 del plan)
    int wls_w[]       = '{1, 1, 1, 1};        // 5, 6, 7, 8 bits
    int stb_w[]       = '{1, 1};              // 1 bit, 1.5/2 bits
    int par_w[]       = '{1, 1, 1, 1, 1};     // ninguna, impar, par, stick1, stick0
    int dl_zero_pct   = 1;                    // % de episodios con DL = 0 (UART deshabilitado)
    int dl_max_fast   = 16;                   // límite superior del rango rápido de DL (1 a 16)
    int dl_max        = 65535;                // límite superior absoluto de DL
    int dl_tail_w[]   = '{30, 8, 2};          // por mil de los episodios: 17-255, 256-4095, 4096-DL_MAX (DL lentos)
    int dl_lsb_first_pct = 10;                // % de episodios que escriben DLL antes que DLM

    // Variables aleatorias (para cada episodio)
    rand bit [1:0]   wls;          // 0..3 = 5..8 bits
    rand bit         stb;          // 0 = 1 bit de parada, 1 = 1.5/2 bits
    rand par_mode_e  par_mode;     // ninguna, impar, par, stick 1, stick 0
    rand bit         eps_free;     // lcr.eps cuando no hay paridad (mueve bits)
    rand bit         sp_free;      // lcr.sp  cuando no hay paridad
    rand bit [15:0]  dl;           // divisor de 16 bits (DLM:DLL)
    rand dl_order_e  dl_order;     // DLM primero o DLL primero

    // Constructor
    function new(string name = "uart_line_cfg");
      super.new(name);
    endfunction

    // LCR armado a partir de los campos (DLAB = 0, break = 0)
    function bit [7:0] lcr_value(bit dlab = 0, bit brk = 0);
      bit pen = (par_mode != PAR_NONE);
      bit eps = pen ? (par_mode == PAR_EVEN || par_mode == PAR_STICK0) : eps_free;
      bit sp  = pen ? (par_mode == PAR_STICK1 || par_mode == PAR_STICK0) : sp_free;
      return {dlab, brk, sp, eps, pen, stb, wls};
    endfunction

    function void parse_plusargs(); // Plusargs para configurar los pesos de las variables aleatorias  
      uart_knobs::get_int_list("UART_LCR_WLS_W",   wls_w);
      uart_knobs::get_int_list("UART_LCR_STB_W",   stb_w);
      uart_knobs::get_int_list("UART_LCR_PAR_W",   par_w);
      uart_knobs::get_int     ("UART_DL_ZERO_PCT", dl_zero_pct);
      uart_knobs::get_int     ("UART_DL_MAX_FAST", dl_max_fast);
      uart_knobs::get_int     ("UART_DL_MAX",      dl_max);
      uart_knobs::get_int_list("UART_DL_TAIL_W",   dl_tail_w);
      uart_knobs::get_int     ("UART_DL_LSB_FIRST_PCT", dl_lsb_first_pct);
    endfunction
  endclass : uart_line_cfg

  // Control del UART: FCR (FIFO), IER (interrupciones) y MCR (módem)
  class uart_ctrl_cfg extends uvm_object;
    `uvm_object_utils(uart_ctrl_cfg)   // macro de UVM: registra la clase en la factory

    // Pesos y parámetros por defecto
    int tl_w[]          = '{1, 1, 1, 1};          // nivel 1, 4, 8, 14
    int fcr_clr_pct     = 50;                     // % de limpiar cada FIFO (RX y TX) al configurar
    int ier_bit_pct[]   = '{50, 50, 50, 50};      // % de cada bit en 1: RDA, THRE, RLS, MS
    int mcr_out_pct     = 50;                     // % en 1 de DTR, RTS, OUT1 y OUT2
    int mcr_loop_pct    = 20;                     // % de episodios en loopback

    rand bit [1:0] tl;             // 0..3 = 1, 4, 8, 14
    rand bit       rx_clr, tx_clr; // limpiar FIFO RX / FIFO TX (FCR[1] y FCR[2])
    rand bit [3:0] ier;            // bits 3:0 de IER
    rand bit       dtr, rts, out1, out2, loop;   // bits 0 a 4 de MCR
    rand bit [3:0] fcr_ign;        // bits 5:4, 3 y 0 (el DUT los ignora)

    // Constructor
    function new(string name = "uart_ctrl_cfg");
      super.new(name);
    endfunction

    // FCR armado a partir de los campos
    function bit [7:0] fcr_value();
      return {tl, fcr_ign[3:2], fcr_ign[1], tx_clr, rx_clr, fcr_ign[0]};
    endfunction

    // MCR armado a partir de los campos
    function bit [7:0] mcr_value();
      return {3'b000, loop, out2, out1, rts, dtr};
    endfunction

    function void parse_plusargs(); // Plusargs para configurar FCR, IER y MCR
      uart_knobs::get_int_list("UART_FCR_TL_W",    tl_w);
      uart_knobs::get_int     ("UART_FCR_CLR_PCT", fcr_clr_pct);
      uart_knobs::get_int_list("UART_IER_BIT_PCT", ier_bit_pct);
      uart_knobs::get_int     ("UART_MCR_OUT_PCT", mcr_out_pct);
      uart_knobs::get_int     ("UART_MCR_LOOP_PCT", mcr_loop_pct);
    endfunction
  endclass : uart_ctrl_cfg

  // Ambiente: episodios, software que atiende, tráfico TX y eventos raros
  class uart_env_cfg extends uvm_object;
    `uvm_object_utils(uart_env_cfg)   // macro de UVM: registra la clase en la factory

    uart_line_cfg line_cfg;   // formato de línea (LCR y DL)
    uart_ctrl_cfg ctrl_cfg;   // FCR, IER y MCR

    // Episodios
    int ep_min          = 5;         // mínimo de episodios por corrida
    int ep_max          = 5;         // máximo de episodios por corrida
    int ep_timeout      = 2000;      // tiempo máximo de un episodio, en Tc (tiempo de carácter)

    // Software que atiende
    int sw_mode_w[]     = '{1, 1};   // interrupciones, sondeo
    int sw_delay_min    = 0;         // retraso mínimo de atención, en Tc
    int sw_delay_max    = 24;        // retraso máximo de atención, en Tc
    int sw_delay_w[]    = '{70, 22, 8};   // pesos de retraso corto, medio y largo
    int sw_poll_max     = 4;         // periodo máximo de sondeo, en Tc
    int sw_partial_pct  = 20;        // % de veces que lee menos datos de los disponibles
    int sw_lsr_first_pct = 80;       // % de veces que lee LSR antes de RBR

    // Transmision
    int tx_bursts_max   = 6;         // ráfagas máximas de escritura a THR por episodio
    int tx_len_max      = 20;        // largo máximo de una ráfaga, en caracteres
    int tx_len_w[]      = '{70, 15, 15};   // pesos de ráfaga corta (1-15), de 16 y de desborde (17-20)
    int tx_blind_pct    = 30;        // % de ráfagas escritas sin revisar THRE
    int tx_gap_max      = 4;         // pausa máxima entre ráfagas, en Tc
    int tx_break_pct    = 5;         // % de episodios con break en TX (LCR[6])
    int tx_break_max    = 4;         // duración máxima del break TX, en Tc
    int data_corner_pct = 20;        // TX y RX (00, FF, 55, AA)

    // Eventos raros
    int reg_noise_pct   = 10;        // % de accesos extra a direcciones al azar
    int reg_dlab_pct    = 20;        // % de esos accesos con DLAB = 1
    int reg_reconfig_pct = 10;       // % de episodios que reescriben LCR, DL, FCR o MCR con tráfico
    int reg_fifo_clr_pct = 10;       // % de episodios que limpian una FIFO con tráfico
    int reg_hw_reset_chk = 1;        // 1 = revisar valores de reset con el RAL al inicio
    int rst_pct         = 5;         // % de episodios con reset asíncrono en medio
    int rst_width_max   = 5;         // ancho máximo del reset, en ciclos

    // Constructor
    function new(string name = "uart_env_cfg");
      super.new(name);
      line_cfg = uart_line_cfg::type_id::create("line_cfg");
      ctrl_cfg = uart_ctrl_cfg::type_id::create("ctrl_cfg");
    endfunction

    function void parse_plusargs(); // Plusargs para pesos y parámetros del ambiente (y de sus line_cfg y ctrl_cfg)
      uart_knobs::get_int     ("UART_SEQ_EP_MIN",       ep_min);
      uart_knobs::get_int     ("UART_SEQ_EP_MAX",       ep_max);
      uart_knobs::get_int     ("UART_SEQ_EP_TIMEOUT",   ep_timeout);
      uart_knobs::get_int_list("UART_SW_MODE_W",        sw_mode_w);
      uart_knobs::get_int     ("UART_SW_DELAY_MIN",     sw_delay_min);
      uart_knobs::get_int     ("UART_SW_DELAY_MAX",     sw_delay_max);
      uart_knobs::get_int_list("UART_SW_DELAY_W",       sw_delay_w);
      uart_knobs::get_int     ("UART_SW_POLL_MAX",      sw_poll_max);
      uart_knobs::get_int     ("UART_SW_PARTIAL_PCT",   sw_partial_pct);
      uart_knobs::get_int     ("UART_SW_LSR_FIRST_PCT", sw_lsr_first_pct);
      uart_knobs::get_int     ("UART_TX_BURSTS_MAX",    tx_bursts_max);
      uart_knobs::get_int     ("UART_TX_LEN_MAX",       tx_len_max);
      uart_knobs::get_int_list("UART_TX_LEN_W",         tx_len_w);
      uart_knobs::get_int     ("UART_TX_BLIND_PCT",     tx_blind_pct);
      uart_knobs::get_int     ("UART_TX_GAP_MAX",       tx_gap_max);
      uart_knobs::get_int     ("UART_TX_BREAK_PCT",     tx_break_pct);
      uart_knobs::get_int     ("UART_TX_BREAK_MAX",     tx_break_max);
      uart_knobs::get_int     ("UART_DATA_CORNER_PCT",  data_corner_pct);
      uart_knobs::get_int     ("UART_REG_NOISE_PCT",    reg_noise_pct);
      uart_knobs::get_int     ("UART_REG_DLAB_PCT",     reg_dlab_pct);
      uart_knobs::get_int     ("UART_REG_RECONFIG_PCT", reg_reconfig_pct);
      uart_knobs::get_int     ("UART_REG_FIFO_CLR_PCT", reg_fifo_clr_pct);
      uart_knobs::get_int     ("UART_REG_HW_RESET_CHK", reg_hw_reset_chk);
      uart_knobs::get_int     ("UART_RST_PCT",          rst_pct);
      uart_knobs::get_int     ("UART_RST_WIDTH_MAX",    rst_width_max);
      line_cfg.parse_plusargs();
      ctrl_cfg.parse_plusargs();
    endfunction
  endclass : uart_env_cfg

  // Agente Wishbone: retardos del driver y accesos con sel inválido
  class wb_agent_cfg extends uvm_object;
    `uvm_object_utils(wb_agent_cfg)   // macro de UVM: registra la clase en la factory

    virtual wb_if vif;   // interfaz virtual del bus Wishbone
    uvm_active_passive_enum is_active = UVM_ACTIVE;   // activo (con driver) o pasivo (solo monitor)

    int wb_gap_max        = 4;     // pausa máxima entre transacciones, en ciclos
    int wb_gap_zero_pct   = 60;    // % de transacciones seguidas sin pausa
    int wb_stb_delay_pct  = 20;    // % de transacciones con stb retrasado respecto a cyc
    int wb_stb_delay_max  = 3;     // retraso máximo de stb, en ciclos
    int wb_bad_sel_pct    = 1;     // % de accesos con wb_sel_i sin exactamente un bit activo (AMB-05)

    // Constructor
    function new(string name = "wb_agent_cfg");
      super.new(name);
    endfunction

    function void parse_plusargs(); // Plusargs para wishbone
      uart_knobs::get_int("UART_WB_GAP_MAX",       wb_gap_max);
      uart_knobs::get_int("UART_WB_GAP_ZERO_PCT",  wb_gap_zero_pct);
      uart_knobs::get_int("UART_WB_STB_DELAY_PCT", wb_stb_delay_pct);
      uart_knobs::get_int("UART_WB_STB_DELAY_MAX", wb_stb_delay_max);
      uart_knobs::get_int("UART_WB_BAD_SEL_PCT",   wb_bad_sel_pct);
    endfunction
  endclass : wb_agent_cfg

  // Agente serie: tráfico RX con errores inyectados
  class uart_ser_agent_cfg extends uvm_object;
    `uvm_object_utils(uart_ser_agent_cfg)   // macro de UVM: registra la clase en la factory

    virtual uart_ser_if vif;   // interfaz virtual de la línea serie
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    int rx_chars_max       = 40;          // caracteres RX máximos por episodio
    int slow_dl            = 256;         // DL desde el cual se limita el tráfico
    int slow_chars_max     = 2;           // caracteres máximos con DL lento
    int rx_gap_max         = 80;          // bits
    int rx_gap_w[]         = '{60, 30, 10};   // pesos de pausa 0, corta y larga
    int parity_err_pct     = 5;           // % de caracteres con paridad corrupta
    int frame_err_pct      = 5;           // % de caracteres con el bit de parada en 0
    int break_pct          = 3;           // % de caracteres reemplazados por break
    int break_extra_max    = 2;           // Tc
    int glitch_pct         = 3;           // % de glitches aislados con la línea en reposo
    int glitch_w_max       = 15;          // 1/16 de bit
    int baud_in_pct        = 10;          // % con desviación de baudios dentro de tolerancia
    int baud_in_max        = 25;          // desviación máxima dentro de tolerancia, en décimas de % (2.5 %)
    int baud_out_pct       = 2;           // % con desviación de baudios fuera de tolerancia
    int baud_out_min       = 50;          // desviación mínima fuera de tolerancia, en décimas de % (5 %)
    int baud_out_max       = 100;         // desviación máxima fuera de tolerancia, en décimas de % (10 %)
    int short_stop_pct     = 5;           // % con 1.5/2 bits de parada en que el agente manda solo 1 (AMB-06)

    // Constructor
    function new(string name = "uart_ser_agent_cfg");
      super.new(name);
    endfunction

    function void parse_plusargs(); // Plusargs para configurar la comunicacion serial
      uart_knobs::get_int     ("UART_SER_RX_CHARS_MAX",   rx_chars_max);
      uart_knobs::get_int     ("UART_SER_SLOW_DL",        slow_dl);
      uart_knobs::get_int     ("UART_SER_SLOW_CHARS_MAX", slow_chars_max);
      uart_knobs::get_int     ("UART_SER_RX_GAP_MAX",     rx_gap_max);
      uart_knobs::get_int_list("UART_SER_RX_GAP_W",       rx_gap_w);
      uart_knobs::get_int     ("UART_SER_PARITY_ERR_PCT", parity_err_pct);
      uart_knobs::get_int     ("UART_SER_FRAME_ERR_PCT",  frame_err_pct);
      uart_knobs::get_int     ("UART_SER_BREAK_PCT",      break_pct);
      uart_knobs::get_int     ("UART_SER_BREAK_EXTRA_MAX", break_extra_max);
      uart_knobs::get_int     ("UART_SER_GLITCH_PCT",     glitch_pct);
      uart_knobs::get_int     ("UART_SER_GLITCH_W_MAX",   glitch_w_max);
      uart_knobs::get_int     ("UART_SER_BAUD_IN_PCT",    baud_in_pct);
      uart_knobs::get_int     ("UART_SER_BAUD_IN_MAX",    baud_in_max);
      uart_knobs::get_int     ("UART_SER_BAUD_OUT_PCT",   baud_out_pct);
      uart_knobs::get_int     ("UART_SER_BAUD_OUT_MIN",   baud_out_min);
      uart_knobs::get_int     ("UART_SER_BAUD_OUT_MAX",   baud_out_max);
      uart_knobs::get_int     ("UART_SER_SHORT_STOP_PCT", short_stop_pct);
    endfunction
  endclass : uart_ser_agent_cfg

  // Agente de módem: cambios en CTS, DSR, RI y DCD
  class modem_agent_cfg extends uvm_object;
    `uvm_object_utils(modem_agent_cfg)   // macro de UVM: registra la clase en la factory

    virtual modem_if vif;   // interfaz virtual de las señales de módem
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    // Pesos y parámetros por defecto
    int mdm_changes_max = 8;               // cambios máximos de módem por episodio
    int mdm_sig_w[]     = '{1, 1, 1, 1};   // CTS, DSR, RI, DCD
    int mdm_gap_max     = 4;               // pausa máxima entre cambios, en Tc
    int mdm_multi_pct   = 10;              // % de cambios de dos señales a la vez

    // Constructor
    function new(string name = "modem_agent_cfg");
      super.new(name);
    endfunction

    function void parse_plusargs(); // Plusargs para configurar la comunicacion de módem
      uart_knobs::get_int     ("UART_MDM_CHANGES_MAX", mdm_changes_max);
      uart_knobs::get_int_list("UART_MDM_SIG_W",       mdm_sig_w);
      uart_knobs::get_int     ("UART_MDM_GAP_MAX",     mdm_gap_max);
      uart_knobs::get_int     ("UART_MDM_MULTI_PCT",   mdm_multi_pct);
    endfunction
  endclass : modem_agent_cfg

  // Scoreboard: chequeos activos, límite de errores y severidad de errores del DUT
  class uart_scb_cfg extends uvm_object;
    `uvm_object_utils(uart_scb_cfg)   // macro de UVM: registra la clase en la factory

    string scb_en       = "all";       // lista: tx,rx,lsr,iir,msr,int
    int    max_errors   = 10;          // detener la corrida tras N errores (0 = nunca)
    string dut_bug_sev  = "warning";   // warning o error (AMB-03, AMB-04, A-MDM-01)

    // Constructor
    function new(string name = "uart_scb_cfg");
      super.new(name);
    endfunction

    // Devuelve 1 si el chequeo 'name' está habilitado.
    function bit chk_enabled(string name);
      if (scb_en == "all") return 1;
      return (find_in_list(scb_en, name) >= 0);
    endfunction

    // Busca 'name' como elemento exacto dentro de una lista separada por comas.
    local function int find_in_list(string list, string name);
      int start = 0;
      for (int n = 0; n <= list.len(); n++) begin
        if (n == list.len() || list[n] == ",") begin
          if (list.substr(start, n - 1) == name) return start;
          start = n + 1;
        end
      end
      return -1;
    endfunction

    // Severidad UVM para las diferencias conocidas del DUT.
    function uvm_severity dut_bug_severity();
      return (dut_bug_sev == "error") ? UVM_ERROR : UVM_WARNING;
    endfunction

    function void parse_plusargs(); // Plusargs para configurar el scoreboard (error fatal si la severidad es inválida)
      uart_knobs::get_str("UART_SCB_EN",          scb_en);
      uart_knobs::get_int("UART_SCB_MAX_ERRORS",  max_errors);
      uart_knobs::get_str("UART_SCB_DUT_BUG_SEV", dut_bug_sev);
      if (dut_bug_sev != "warning" && dut_bug_sev != "error")   // solo se aceptan esos dos valores
        `uvm_fatal("KNOBS", $sformatf("+UART_SCB_DUT_BUG_SEV debe ser warning o error, no '%s'", dut_bug_sev))
    endfunction
  endclass : uart_scb_cfg

  // Cobertura funcional: habilitación y curva [COV_CURVE]
  class uart_cov_cfg extends uvm_object;
    `uvm_object_utils(uart_cov_cfg)   // macro de UVM: registra la clase en la factory

    int cov_en          = 1;   // 1 = habilita la cobertura funcional
    int cov_curve_every = 1;   // imprime [COV_CURVE] cada N episodios (0 = no)

    // Constructor
    function new(string name = "uart_cov_cfg");
      super.new(name);
    endfunction

    function void parse_plusargs(); // Plusargs para configurar la cobertura
      uart_knobs::get_int("UART_COV_EN",          cov_en);
      uart_knobs::get_int("UART_COV_CURVE_EVERY", cov_curve_every);
    endfunction
  endclass : uart_cov_cfg

  // ---------------------------------------------------------------------------
  // Componentes del ambiente (cada integrante agrega los suyos, en este orden)
  // ---------------------------------------------------------------------------
  // Agente Wishbone (Leonardo). Son .sv pero NO van en filelist.f: se compilan
  // solo a través de estos `include (cada archivo define clases de este paquete).
  `include "wishbone_agent/wb_item.sv"
  `include "wishbone_agent/wb_events.sv"
  `include "wishbone_agent/wb_driver.sv"
  `include "wishbone_agent/wb_sequencer.sv"
  `include "wishbone_agent/wb_monitor.sv"
  `include "wishbone_agent/uart_int_monitor.sv"
  `include "wishbone_agent/wb_agent.sv"
  `include "wishbone_agent/wb_seqs.sv"

endpackage : uart_pkg
