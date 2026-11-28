`uvm_analysis_imp_decl(_wb)
`uvm_analysis_imp_decl(_rst)
`uvm_analysis_imp_decl(_int)
`uvm_analysis_imp_decl(_tx)
`uvm_analysis_imp_decl(_rx)
`uvm_analysis_imp_decl(_mdm)

// un caracter esperado, chk = 0 si no es predecible y solo se cuenta
typedef struct {
  bit [7:0] data;
  bit       chk;
  bit       pisado;  // una escritura con la FIFO llena le cayo encima (AMB-10)
  bit [7:0] orig;    // lo que se escribio de verdad, para el mensaje
  string    porque;  // si chk = 0, por que no se compara
  realtime  t;       // cuando lo vio el monitor
} uart_exp_t;

class uart_scoreboard extends uvm_scoreboard;
    // Registro en la Factory
  `uvm_component_utils(uart_scoreboard)

  uart_scb_cfg cfg;

  uart_exp_t tx_q[$];        // escritos en THR que todavia no salen por stx
  uart_exp_t rx_q[$];        // vistos en srx que todavia no se leen de RBR

  bit [7:0] exp_lsr;         // Estado esperado del Line Status Register
  bit [7:0] exp_iir;         // Estado esperado del Interrupt Identification Register
  bit [7:0] exp_msr;         // Estado esperado del Modem Status Register

  bit       dlab_bit;        // Rastreo del bit DLAB para resolver direcciones
  bit [7:0] lcr_val;         // LCR y MCR segun lo que paso por el bus
  bit [7:0] mcr_val;
  bit [15:0] dl_val;         // DLM y DLL segun el bus, con 0 el RTL nunca genera enable y no hay baudios
  bit       tx_dirty;       // hubo reconfig, limpieza o reset con trafico, no se compara hasta el fin del episodio
  bit       rx_dirty;
  bit       rx_seen;         // ya llego algun caracter por srx en este episodio
  bit       rst_tx_busy, rst_rx_busy;
  int       error_count;
  int       n_tx_ok, n_rx_ok, n_skip;
  string    motivo_tx, motivo_rx;   // por que se dejo de comparar TX y RX
  int       sin_comparar[string];   // cuantos quedaron sin comparar por cada motivo
  int       tx_desde_vacia;         // escrituras en THR desde que LSR dijo FIFO TX vacia
  bit       tx_resync_ok;           // se dejo de comparar solo por FIFO llena, con TEMT se vuelve a comparar
  bit       thr_en_loop;            // se escribio THR en loopback y puede seguir en la FIFO TX
  bit       temt_visto;             // la ultima lectura de LSR tenia TEMT y despues no se escribio THR
  bit [1:0] pin_mdm;                // rts y dtr que vio el monitor de modem la ultima vez
  bit       pin_visto;              // el monitor solo manda cuando algo cambia, antes de eso no sabemos los pines
  bit       mdm_pend;               // cambio MCR o los pines, falta revisar
  int       n_mdm_ok, n_mdm_amb;

  // Puertos TLM
  uvm_analysis_imp_wb  #(wb_item, uart_scoreboard)       wb_imp;
  uvm_analysis_imp_rst #(wb_rst_item, uart_scoreboard)   rst_imp;
  uvm_analysis_imp_int #(uart_int_item, uart_scoreboard) int_imp;
  uvm_analysis_imp_tx  #(ser_item, uart_scoreboard)      tx_imp;
  uvm_analysis_imp_rx  #(ser_item, uart_scoreboard)      rx_imp;
  uvm_analysis_imp_mdm #(mdm_item, uart_scoreboard)      mdm_imp;
  uvm_analysis_port    #(uart_model_evt)                 ap;

  // constructor
  function new(string name = "uart_scoreboard", uvm_component parent);
    super.new(name, parent);
  endfunction

  // toma la cfg, crea los puertos TLM y deja el modelo en su estado de reset
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(uart_scb_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("NO_CFG", "Falta uart_scb_cfg en el scoreboard")
    end
    wb_imp  = new("wb_imp", this);
    rst_imp = new("rst_imp", this);
    int_imp = new("int_imp", this);
    tx_imp  = new("tx_imp", this);
    rx_imp  = new("rx_imp", this);
    mdm_imp = new("mdm_imp", this);
    ap      = new("ap", this);
    reset_model();
  endfunction

  // al final de cada episodio la secuencia ya vacio TX y RX, asi que ahi revisamos y empezamos limpio
  virtual task run_phase(uvm_phase phase);
    uvm_event ep_end = uvm_event_pool::get_global("uart_ep_end");
    forever begin
      ep_end.wait_trigger();
      // si la secuencia no llego a ver TEMT lo que quedo en la FIFO TX sale en el siguiente episodio
      if (!temt_visto && !tx_dirty) begin
        ensuciar_tx("episodio terminado sin TEMT");
        if (tx_dirty) tx_resync_ok = 1;   // con el proximo TEMT ya se puede volver a comparar
      end
      check_left("fin de episodio");
      rx_q.delete();
      rx_dirty = 0;
      rx_seen  = 0;
      motivo_rx = "";
      if (temt_visto) begin
        tx_q.delete();
        tx_dirty = 0;
        motivo_tx = "";
        tx_desde_vacia = 0;
        thr_en_loop = 0;
      end else if (thr_en_loop) begin
        // lo de loopback todavia puede caer en la FIFO RX ya empezado el otro episodio
        rx_dirty  = 1;
        rx_seen   = 1;
        motivo_rx = "loopback del episodio anterior";
      end
      revisar_mdm();
    end
  endtask

  // vacia las colas y deja los registros copiados con su valor de reset
  function void reset_model();
    tx_q.delete();
    rx_q.delete();
    exp_lsr  = 8'h60; // THRE y TEMT en 1 (transmisor vacío)
    exp_iir  = 8'hC1; // Sin interrupciones pendientes
    exp_msr  = 8'h00;
    dlab_bit = 1'b0;
    lcr_val  = 8'h03;  // valor de reset del RTL
    mcr_val  = 8'h00;
    dl_val   = 16'h0000;  // el RTL arranca con DL en 0 hasta que lo configuren
    tx_desde_vacia = 0;
    thr_en_loop = 0;
    temt_visto = 1;   // con el reset las FIFO quedan vacias
    mdm_pend = 1;   // MCR vuelve a 0 y los pines tienen que seguirlo
  endfunction

  // mascara de los bits de dato validos segun LCR[1:0] (5 a 8 bits)
  function bit [7:0] data_mask();
    return 8'hFF >> (3 - lcr_val[1:0]);
  endfunction

  // el monitor avisa en la mitad de la parada y el DUT guarda el caracter hasta unos 2 DL ciclos despues
  function bit recien_llegado(bit [7:0] rd8);
    realtime ventana = (3 * cfg.line.bit_cycles() / 16 + 8) * UART_CLK_NS * 1ns;
    return ((rd8 & data_mask()) !== rx_q[0].data) && ($realtime - rx_q[0].t < ventana);
  endfunction

  // hay caracteres esperando salir por stx
  function bit tx_busy(); 
    return tx_q.size() > 0; 
  endfunction

  // hay caracteres esperando ser leidos de RBR
  function bit rx_busy();
    return rx_q.size() > 0; 
  endfunction

  // lo que quedo esperando al final es que nunca llego
  function void check_left(string donde);
    int n_tx = 0, n_rx = 0;
    if (!tx_dirty) foreach (tx_q[i]) if (tx_q[i].chk) n_tx++;
    if (!rx_dirty) foreach (rx_q[i]) if (rx_q[i].chk) n_rx++;
    if (n_tx > 0) begin
      error_count++;
      `uvm_error("SCB_TX", $sformatf("%s: quedaron %0d caracteres escritos en THR que nunca salieron por stx", donde, n_tx))
    end
    if (n_rx > 0) begin
      error_count++;
      `uvm_error("SCB_RX", $sformatf("%s: quedaron %0d caracteres recibidos que nunca se leyeron de RBR", donde, n_rx))
    end
  endfunction

  // desde aqui no se compara lo que este en camino, se cuenta nada mas
  function void ensuciar_tx(string porque);
    // si fue solo por FIFO llena, al leer TEMT se puede volver a comparar
    if (tx_dirty && porque != "FIFO TX llena") tx_resync_ok = 0;
    // lo que se escribio en loopback no esta en tx_q pero igual puede salir por stx
    if ((!tx_busy() && !thr_en_loop) || tx_dirty) return;
    tx_dirty     = 1;
    tx_resync_ok = (porque == "FIFO TX llena");
    motivo_tx    = porque;
    foreach (tx_q[i]) begin
      tx_q[i].chk    = 0;
      tx_q[i].porque = porque;
    end
    `uvm_info("SCB", {"TX no predecible hasta el fin del episodio: ", porque}, UVM_MEDIUM)
  endfunction

  // igual que ensuciar_tx pero para los caracteres de RX
  function void ensuciar_rx(string porque);
    if (!(rx_busy() || rx_seen) || rx_dirty) return;
    rx_dirty  = 1;
    motivo_rx = porque;
    foreach (rx_q[i]) begin
      if (rx_q[i].chk) rx_q[i].porque = porque;   // se queda con el primer motivo
      rx_q[i].chk = 0;
    end
    `uvm_info("SCB", {"RX no predecible hasta el fin del episodio: ", porque}, UVM_MEDIUM)
  endfunction

  // cuenta un caracter que no se comparo, por su motivo
  function void contar_skip(uart_exp_t exp);
    n_skip++;
    if (exp.porque == "") exp.porque = "chequeo apagado en la cfg";
    sin_comparar[exp.porque]++;
  endfunction

  // reporta una diferencia conocida del DUT con la severidad de la cfg
  function void dut_bug(string amb, string msg);
    if (cfg.dut_bug_sev == UVM_ERROR) `uvm_error("DUT_BUG", {amb, ": ", msg})
    else                              `uvm_warning("DUT_BUG", {amb, ": ", msg})
  endfunction

  // publica un evento del modelo hacia la cobertura
  function void send_evt(uart_evt_e kind, int unsigned tx_lvl, int unsigned rx_lvl, bit lost);
    uart_model_evt evt = uart_model_evt::type_id::create("evt");
    evt.kind     = kind;
    evt.tx_level = tx_lvl;
    evt.rx_level = rx_lvl;
    evt.lost     = lost;
    evt.tx_busy  = tx_busy();
    evt.rx_busy  = rx_busy();
    ap.write(evt);
  endfunction

  // Manejo del Reset: al subir reinicia el modelo, al bajar manda EV_RESET con el ancho
  virtual function void write_rst(wb_rst_item item);
    uart_model_evt evt;

    if (item.asserted) begin
      rst_tx_busy = tx_busy();
      rst_rx_busy = rx_busy() || rx_seen;
      // un caracter cortado por el reset igual lo pueden reportar los monitores
      if (!item.is_initial) begin
        tx_dirty  = 1;
        rx_dirty  = 1;
        tx_resync_ok = 0;
        motivo_tx = "reset a media prueba";
        motivo_rx = "reset a media prueba";
      end
      reset_model();
    end else begin
      // el ancho del reset solo se sabe cuando baja
      evt = uart_model_evt::type_id::create("evt");
      evt.kind       = EV_RESET;
      evt.rst_cycles = item.width_cycles;
      evt.tx_busy    = rst_tx_busy;
      evt.rx_busy    = rst_rx_busy;
      ap.write(evt);
    end
  endfunction

  // 2. Manejo del Bus Wishbone, sigue LCR, MCR, FCR y DL, encola THR y compara RBR
  virtual function void write_wb(wb_item item);
    bit [4:0] reg_idx;
    bit [7:0] dat8, rd8;
    uart_exp_t exp;
    int unsigned lvl;

    // Ignorar accesos abortados o que no recibieron ack a tiempo
    if (item.timeout || item.aborted) begin
      `uvm_info("SCB_DBG", $sformatf("acceso ignorado adr %0d we %0b (timeout %0b, abortado %0b)", item.adr, item.we, item.timeout, item.aborted), UVM_HIGH)
      return;
    end

    // el registro y el byte que de verdad uso el DUT, igual que la cobertura
    reg_idx = uart_reg_of(item.adr, item.sel);
    dat8    = uart_lane8(item.sel, item.dat);
    rd8     = uart_lane8(item.sel, item.dat_rd);

    // el DUT cambia los pines antes del ack, asi que con la propia escritura a MCR todavia no revisamos
    if (!(item.we && reg_idx == UART_MCR)) revisar_mdm();

    if (item.we) begin
      `uvm_info("SCB_DBG", $sformatf("escritura reg %0d = %02h con DLAB %0b", reg_idx, dat8, dlab_bit), UVM_HIGH)
      case (reg_idx)
        UART_LCR: begin
          if (dat8[6:0] != lcr_val[6:0]) begin
            ensuciar_tx("cambio de LCR");
            ensuciar_rx("cambio de LCR");
          end
          lcr_val  = dat8;
          dlab_bit = dat8[7];
        end
        UART_MCR: begin
          if (dat8[4] != mcr_val[4]) begin
            ensuciar_tx("cambio de loopback");
            ensuciar_rx("cambio de loopback");
          end
          mcr_val = dat8;
          mdm_pend = 1;
        end
        UART_FCR: begin   // el RTL escribe FCR sin importar DLAB
          // el caracter en curso no se corta, pero no sabemos cuantos quedaban en la FIFO
          if (dat8[2]) begin
            ensuciar_tx("limpieza de la FIFO TX");
            tx_desde_vacia = 0;
            thr_en_loop = 0;
          end
          if (dat8[1]) begin
            ensuciar_rx("limpieza de la FIFO RX");
            rx_q.delete();
          end
        end
        default: ;
      endcase

      // escribir DLL o DLM reinicia el contador de baudios aunque el valor sea el mismo
      if (dlab_bit && (reg_idx == UART_DLL || reg_idx == UART_DLM)) begin
        ensuciar_tx("escritura de DL");
        ensuciar_rx("escritura de DL");
        if (reg_idx == UART_DLL) dl_val[7:0]  = dat8;
        else                     dl_val[15:8] = dat8;
      end

      // escritura en THR (DLAB = 0)
      if (reg_idx == UART_THR && !dlab_bit) begin
        temt_visto = 0;
        lvl = tx_q.size();
        exp.data  = dat8 & data_mask();
        exp.chk   = !tx_dirty;
        exp.pisado = 0;
        if (mcr_val[4]) begin
          // en loopback el caracter vuelve por el receptor y no sale por stx
          exp.chk    = 0;
          exp.porque = "loopback";
          thr_en_loop = 1;
          rx_q.push_back(exp);
          send_evt(EV_THR_WRITE, lvl, rx_q.size(), 0);
          return;
        end
        // con la FIFO llena el DUT escribe encima (AMB-10) y ya no sabemos que sale
        tx_desde_vacia++;
        if (lvl >= 16 && tx_desde_vacia >= 17) ensuciar_tx("FIFO TX llena");  // tienen que cumplirse las dos
        if (lvl >= 17 && tx_desde_vacia >= 17) begin
          send_evt(EV_THR_WRITE, 16, rx_q.size(), 1);
          return;
        end
        exp.chk    = !tx_dirty;   // pudo cambiar justo arriba
        exp.porque = motivo_tx;
        // con DL = 0 el caracter se queda en la FIFO y nunca sale por stx
        if (dl_val == 0) begin
          exp.chk    = 0;
          exp.porque = "DL = 0";
        end
        tx_q.push_back(exp);
        `uvm_info("SCB_DBG", $sformatf("THR %02h, en cola %0d, chk %0b", exp.data, tx_q.size(), exp.chk), UVM_HIGH)
        send_evt(EV_THR_WRITE, lvl, rx_q.size(), 0);
      end
    end
    else begin
      // lectura de RBR (DLAB = 0)
      if (reg_idx == UART_RBR && !dlab_bit) begin
        lvl = rx_q.size();
        `uvm_info("SCB_DBG", $sformatf("RBR %02h, en cola %0d, primero %02h chk %0b", rd8, lvl, (lvl > 0) ? rx_q[0].data : 8'h00, (lvl > 0) ? rx_q[0].chk : 1'b0), UVM_HIGH)
        // si el primero acaba de llegar y no calza, el DUT todavia no lo tenia y la FIFO estaba vacia
        if (lvl > 0 && recien_llegado(rd8)) begin
          `uvm_info("SCB_DBG", "RBR leido antes de que el DUT guardara el caracter", UVM_HIGH)
          lvl = 0;
        end
        // leer con la FIFO vacia no se compara (V-RX-05)
        if (lvl > 0) begin
          exp = rx_q.pop_front();
          if (exp.chk && cfg.chk_rx) begin
            if ((rd8 & data_mask()) !== exp.data) begin
              error_count++;
              `uvm_error("SCB_RX", $sformatf("RBR leyo %02h y se esperaba %02h (%s)", rd8 & data_mask(), exp.data, cfg.line.convert2string()))
            end else if (exp.pisado) begin
              dut_bug("AMB-10", $sformatf("RBR leyo %02h, que llego con la FIFO RX llena, en vez de %02h", exp.data, exp.orig));
            end else n_rx_ok++;
          end else contar_skip(exp);
        end
        send_evt(EV_RBR_READ, tx_q.size(), lvl, 0);
      end
      if (reg_idx == UART_LSR) leer_lsr(rd8);
    end
  endfunction

  // LSR[5] y LSR[6] solo bajan con una escritura en THR, si se leen en 1 la FIFO TX sigue vacia
  function void leer_lsr(bit [7:0] lsr);
    temt_visto = lsr[6];
    if (mcr_val[4]) begin   // en loopback tx_q no se usa
      if (lsr[6]) thr_en_loop = 0;   // ya salio todo por dentro
      return;
    end
    if (lsr[5]) tx_desde_vacia = 0;
    // TEMT, ya salio todo por stx, lo que quede en cola nunca va a salir
    if (lsr[6] && (!tx_dirty || tx_resync_ok) && !lcr_val[6]) begin
      foreach (tx_q[i]) begin
        if (tx_q[i].chk && cfg.chk_tx) begin
          error_count++;
          `uvm_error("SCB_TX", $sformatf("LSR dice transmisor vacio y %02h nunca salio por stx", tx_q[i].data))
        end else contar_skip(tx_q[i]);
      end
      tx_q.delete();
      // el DUT quedo limpio, lo que se escriba de aqui en adelante si se puede comparar
      if (tx_dirty) `uvm_info("SCB", "TX vacio segun LSR, se vuelve a comparar TX", UVM_MEDIUM)
      tx_dirty  = 0;
      motivo_tx = "";
    end
  endfunction

  // caracter que salio por stx, tiene que ser el primero que se escribio en THR
  virtual function void write_tx(ser_item item);
    uart_exp_t exp;
    bit [7:0]  got;

    if (item.err == SER_BREAK) return;   // break de LCR[6], no es un caracter
    got = item.data & data_mask();
    `uvm_info("SCB_DBG", $sformatf("stx %02h err %s, en cola %0d, primero %02h chk %0b", got, item.err.name(), tx_q.size(), (tx_q.size() > 0) ? tx_q[0].data : 8'h00, (tx_q.size() > 0) ? tx_q[0].chk : 1'b0), UVM_HIGH)

    if (tx_q.size() == 0) begin
      if (tx_dirty) return;
      error_count++;
      `uvm_error("SCB_TX", $sformatf("salio %02h por stx sin que nadie lo escribiera en THR", got))
      return;
    end

    exp = tx_q.pop_front();
    if (!exp.chk || !cfg.chk_tx) begin
      contar_skip(exp);
      return;
    end

    if (got !== exp.data) begin
      error_count++;
      `uvm_error("SCB_TX", $sformatf("stx saco %02h y se esperaba %02h (%s)", got, exp.data, cfg.line.convert2string()))
    end else if (item.err != SER_OK) begin
      error_count++;
      `uvm_error("SCB_TX", $sformatf("el caracter %02h salio con error %s", got, item.err.name()))
    end else n_tx_ok++;
  endfunction

  // caracter que entro por srx, el DUT lo mete a la FIFO RX
  virtual function void write_rx(ser_item item);
    uart_exp_t exp;
    int unsigned lvl = rx_q.size();

    `uvm_info("SCB_DBG", $sformatf("srx %02h err %s, en cola %0d", item.data, item.err.name(), lvl), UVM_HIGH)
    if (mcr_val[4]) return;   // en loopback el DUT ignora srx
    rx_seen = 1;

    // con DL = 0 el receptor del DUT no avanza y el caracter nunca entra a la FIFO
    if (dl_val == 0) begin
      n_skip++;
      sin_comparar["DL = 0"]++;
      return;
    end

    // el RTL guarda el del overrun encima del mas viejo aunque no lo cuente
    if (lvl >= 16) begin
      if (!rx_q[0].pisado) rx_q[0].orig = rx_q[0].data;
      rx_q[0].pisado = 1;
      rx_q[0].data   = item.data & data_mask();
      if (item.err inside {SER_BAUD_OUT, SER_GLITCH_START}) begin
        rx_q[0].chk    = 0;
        rx_q[0].porque = $sformatf("caracter con %s", item.err.name());
      end
      send_evt(EV_RX_PUSH, tx_q.size(), lvl, 1);
      return;
    end

    exp.data   = item.data & data_mask();
    exp.pisado = 0;
    exp.t      = $realtime;
    // fuera de tolerancia o falso inicio, el DUT pudo leer otra cosa
    exp.chk   = !rx_dirty && !(item.err inside {SER_BAUD_OUT, SER_GLITCH_START});
    exp.porque = rx_dirty ? motivo_rx : $sformatf("caracter con %s", item.err.name());
    rx_q.push_back(exp);
    // el DUT pudo recibir uno de mas o de menos, ya no se puede confiar en la cuenta
    if (!exp.chk) ensuciar_rx($sformatf("caracter con %s", item.err.name()));
    send_evt(EV_RX_PUSH, tx_q.size(), lvl, 0);
  endfunction

  // (write_int se mantiene vacía por ahora)
  virtual function void write_int(uart_int_item item); endfunction

  // guarda los pines rts y dtr; se revisan en el siguiente acceso al bus, este monitor y el de Wishbone no siempre llegan en orden
  virtual function void write_mdm(mdm_item item);
    if (!pin_visto || {item.rts, item.dtr} != pin_mdm) mdm_pend = 1;
    pin_mdm   = {item.rts, item.dtr};
    pin_visto = 1;
  endfunction

  // V-MDM-01, la especificacion dice que rts y dtr salen invertidos respecto a MCR[1:0]
  function void revisar_mdm();
    bit [1:0] mcr_bits = mcr_val[1:0];
    if (!mdm_pend || !pin_visto) return;
    mdm_pend = 0;
    if (pin_mdm == ~mcr_bits) n_mdm_ok++;
    else if (pin_mdm == mcr_bits) begin   // el RTL los saca sin invertir
      n_mdm_amb++;
      dut_bug("AMB-03", $sformatf("rts/dtr = %b%b con MCR[1:0] = %b%b (se esperaba el complemento)", pin_mdm[1], pin_mdm[0], mcr_bits[1], mcr_bits[0]));
    end else begin
      error_count++;
      `uvm_error("SCB_MDM", $sformatf("rts/dtr = %b%b no calza con MCR[1:0] = %b%b de ninguna forma", pin_mdm[1], pin_mdm[0], mcr_bits[1], mcr_bits[0]))
    end
  endfunction

  // al terminar la corrida revisa lo que quedo sin salir o sin leer y los pines del modem
  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    check_left("fin de la prueba");
    revisar_mdm();
  endfunction

  // imprime los conteos de lo comparado, lo que no se pudo comparar y los motivos
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB", $sformatf("TX bien: %0d, RX bien: %0d, sin comparar: %0d, errores: %0d",
              n_tx_ok, n_rx_ok, n_skip, error_count), UVM_LOW)
    `uvm_info("SCB", $sformatf("rts/dtr bien: %0d, con AMB-03: %0d", n_mdm_ok, n_mdm_amb), UVM_LOW)
    foreach (sin_comparar[motivo])
      `uvm_info("SCB", $sformatf("sin comparar por %s: %0d", motivo, sin_comparar[motivo]), UVM_LOW)
  endfunction
endclass : uart_scoreboard