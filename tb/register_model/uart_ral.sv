//////////////////////////////////////////////////////////////////////
// uart_ral.sv: modelo de registros (RAL) del UART 16550           
//
// Contiene los registros, uart_reg_block, el
// adaptador y el predictor
//////////////////////////////////////////////////////////////////////

// Registro base
class uart_reg_base extends uvm_reg;
  `uvm_object_utils(uart_reg_base)

  // Constructor
  function new(string name = "uart_reg_base", int unsigned n_bits = 8);
    super.new(name, n_bits, UVM_NO_COVERAGE);
  endfunction

  // Crea y configura un campo. check = 0 lo deja fuera de mirror y los campos volátiles quedan con check = 1 
  protected function uvm_reg_field fld(string name, int unsigned size, int unsigned lsb,
                                       string access, bit vol, uvm_reg_data_t rst, bit check = 1);
    uvm_reg_field f = uvm_reg_field::type_id::create(name);   // crea el objeto con la factory
    f.configure(this, size, lsb, access, vol, rst, 1, (access == "RW"), 0);
    f.set_compare(check ? UVM_CHECK : UVM_NO_CHECK);
    return f;
  endfunction
endclass : uart_reg_base

// FIFO RX 
class uart_reg_rbr extends uart_reg_base;
  `uvm_object_utils(uart_reg_rbr)
  uvm_reg_field data;

  function new(string name = "rbr"); 
   super.new(name); 
  endfunction

  virtual function void build();
    data = fld("data", 8, 0, "RO", 1, 8'h00);
  endfunction
endclass : uart_reg_rbr

// FIFO TX
class uart_reg_thr extends uart_reg_base;
  `uvm_object_utils(uart_reg_thr)
  uvm_reg_field data;

  function new(string name = "thr"); 
   super.new(name); 
  endfunction

  virtual function void build();
    data = fld("data", 8, 0, "WO", 1, 8'h00);
  endfunction
endclass : uart_reg_thr

// IER, bits 3:0 de interrupciones habilitadas, 7:4 reservados
class uart_reg_ier extends uart_reg_base;
  `uvm_object_utils(uart_reg_ier)
  uvm_reg_field rda;
  uvm_reg_field thre;
  uvm_reg_field rls;
  uvm_reg_field ms;
  uvm_reg_field rsv;

  function new(string name = "ier"); 
   super.new(name); 
  endfunction

  virtual function void build();
    rda  = fld("rda",  1, 0, "RW", 0, 1'b0);
    thre = fld("thre", 1, 1, "RW", 0, 1'b0);
    rls  = fld("rls",  1, 2, "RW", 0, 1'b0);
    ms   = fld("ms",   1, 3, "RW", 0, 1'b0);
    rsv  = fld("rsv",  4, 4, "RO", 0, 4'h0);
  endfunction
endclass : uart_reg_ier

// IIR: estado de interrupción 
class uart_reg_iir extends uart_reg_base;
  `uvm_object_utils(uart_reg_iir)
  uvm_reg_field pending;
  uvm_reg_field id;
  uvm_reg_field rsv;
  uvm_reg_field comp;

  function new(string name = "iir"); 
   super.new(name); 
  endfunction

  virtual function void build();
    pending = fld("pending", 1, 0, "RO", 1, 1'b1);
    id      = fld("id",      3, 1, "RO", 1, 3'b000);
    rsv     = fld("rsv",     2, 4, "RO", 0, 2'b00);
    comp    = fld("comp",    2, 6, "RO", 0, 2'b11);
  endfunction

  // Leer IIR con THRE pendiente (id = 001) 
  virtual function void do_predict(uvm_reg_item rw, uvm_predict_e kind = UVM_PREDICT_DIRECT,
                                   uvm_reg_byte_en_t be = -1);
    if (kind == UVM_PREDICT_READ && rw.value[0][3:0] == 4'b0010)
      rw.value[0] = 8'hC1;
    super.do_predict(rw, kind, be);
  endfunction
endclass : uart_reg_iir

// FCR: solo escritura con reset 0xC0 
class uart_reg_fcr extends uart_reg_base;
  `uvm_object_utils(uart_reg_fcr)
  uvm_reg_field ign0;
  uvm_reg_field rx_clr;
  uvm_reg_field tx_clr;
  uvm_reg_field ign;
  uvm_reg_field tl;

  function new(string name = "fcr"); 
   super.new(name); 
  endfunction

  virtual function void build();
    ign0   = fld("ign0",   1, 0, "WO", 0, 1'b0);
    rx_clr = fld("rx_clr", 1, 1, "WO", 0, 1'b0);
    tx_clr = fld("tx_clr", 1, 2, "WO", 0, 1'b0);
    ign    = fld("ign",    3, 3, "WO", 0, 3'b000);
    tl     = fld("tl",     2, 6, "WO", 0, 2'b11);
  endfunction
endclass : uart_reg_fcr

// LCR
class uart_reg_lcr extends uart_reg_base;
  `uvm_object_utils(uart_reg_lcr)
  uvm_reg_field wls;
  uvm_reg_field stb;
  uvm_reg_field pen;
  uvm_reg_field sp;
  uvm_reg_field eps;
  uvm_reg_field bc;
  uvm_reg_field dlab;

  function new(string name = "lcr"); 
   super.new(name); 
  endfunction

  virtual function void build();
    wls  = fld("wls",  2, 0, "RW", 0, 2'b11);
    stb  = fld("stb",  1, 2, "RW", 0, 1'b0);
    pen  = fld("pen",  1, 3, "RW", 0, 1'b0);
    eps  = fld("eps",  1, 4, "RW", 0, 1'b0);
    sp   = fld("sp",   1, 5, "RW", 0, 1'b0);
    bc   = fld("bc",   1, 6, "RW", 0, 1'b0);
    dlab = fld("dlab", 1, 7, "RW", 0, 1'b0);
  endfunction
endclass : uart_reg_lcr

// MCR
class uart_reg_mcr extends uart_reg_base;
  `uvm_object_utils(uart_reg_mcr)
  uvm_reg_field dtr;
  uvm_reg_field rts;
  uvm_reg_field out1;
  uvm_reg_field out2;
  uvm_reg_field loop;
  uvm_reg_field ign;

  function new(string name = "mcr"); 
   super.new(name); 
  endfunction

  virtual function void build();
    dtr  = fld("dtr",  1, 0, "WO", 0, 1'b0);
    rts  = fld("rts",  1, 1, "WO", 0, 1'b0);
    out1 = fld("out1", 1, 2, "WO", 0, 1'b0);
    out2 = fld("out2", 1, 3, "WO", 0, 1'b0);
    loop = fld("loop", 1, 4, "WO", 0, 1'b0);
    ign  = fld("ign",  3, 5, "WO", 0, 3'b000);
  endfunction
endclass : uart_reg_mcr

// LSR
class uart_reg_lsr extends uart_reg_base;
  `uvm_object_utils(uart_reg_lsr)
  uvm_reg_field dr;
  uvm_reg_field oe;
  uvm_reg_field pe;
  uvm_reg_field fe;
  uvm_reg_field bi;
  uvm_reg_field thre;
  uvm_reg_field temt;
  uvm_reg_field err;

  function new(string name = "lsr"); 
    super.new(name); 
  endfunction

  virtual function void build();
    dr   = fld("dr",   1, 0, "RO", 1, 1'b0);
    oe   = fld("oe",   1, 1, "RC", 1, 1'b0);
    pe   = fld("pe",   1, 2, "RC", 1, 1'b0);
    fe   = fld("fe",   1, 3, "RC", 1, 1'b0);
    bi   = fld("bi",   1, 4, "RC", 1, 1'b0);
    thre = fld("thre", 1, 5, "RO", 1, 1'b1);
    temt = fld("temt", 1, 6, "RO", 1, 1'b1);
    err  = fld("err",  1, 7, "RO", 1, 1'b0);
  endfunction
endclass : uart_reg_lsr

// MSR
class uart_reg_msr extends uart_reg_base;
  `uvm_object_utils(uart_reg_msr)
  uvm_reg_field dcts;
  uvm_reg_field dsr;
  uvm_reg_field ddsr;
  uvm_reg_field teri;
  uvm_reg_field ddcd;
  uvm_reg_field cts;
  uvm_reg_field ri;
  uvm_reg_field dcd;

  function new(string name = "msr"); 
   super.new(name); 
   endfunction

  virtual function void build();
    dcts = fld("dcts", 1, 0, "RC", 1, 1'b0);
    ddsr = fld("ddsr", 1, 1, "RC", 1, 1'b0);
    teri = fld("teri", 1, 2, "RC", 1, 1'b0);
    ddcd = fld("ddcd", 1, 3, "RC", 1, 1'b0);
    cts  = fld("cts",  1, 4, "RO", 1, 1'b0, 0);
    dsr  = fld("dsr",  1, 5, "RO", 1, 1'b0, 0);
    ri   = fld("ri",   1, 6, "RO", 1, 1'b0, 0);
    dcd  = fld("dcd",  1, 7, "RO", 1, 1'b0, 0);
  endfunction
endclass : uart_reg_msr

// SCR, DLL y DLM, registros de 8 bits que guardan lo que se les escribe
class uart_reg_byte extends uart_reg_base;
  `uvm_object_utils(uart_reg_byte)
  uvm_reg_field data;

  function new(string name = "uart_reg_byte"); 
    super.new(name); 
  endfunction

  virtual function void build();
    data = fld("data", 8, 0, "RW", 0, 8'h00);
  endfunction
endclass : uart_reg_byte

// Debug 1
class uart_reg_dbg1 extends uart_reg_base;
  `uvm_object_utils(uart_reg_dbg1)
  uvm_reg_field lsr;
  uvm_reg_field ier;
  uvm_reg_field iir;
  uvm_reg_field lcr;
  uvm_reg_field msr_lo;
  uvm_reg_field msr_hi;

  function new(string name = "dbg1"); 
   super.new(name, 32);
  endfunction

  virtual function void build();
    lsr    = fld("lsr",    8,  0, "RO", 1, 8'h60);
    ier    = fld("ier",    4,  8, "RO", 1, 4'h0);
    iir    = fld("iir",    4, 12, "RO", 1, 4'h1);
    lcr    = fld("lcr",    8, 16, "RO", 1, 8'h03);
    msr_lo = fld("msr_lo", 4, 24, "RO", 1, 4'h0);
    msr_hi = fld("msr_hi", 4, 28, "RO", 1, 4'h0, 0);
  endfunction
endclass : uart_reg_dbg1

// Debug 2
class uart_reg_dbg2 extends uart_reg_base;
  `uvm_object_utils(uart_reg_dbg2)
  uvm_reg_field tx_fsm;
  uvm_reg_field tx_cnt;
  uvm_reg_field rx_fsm;
  uvm_reg_field rx_cnt;
  uvm_reg_field mcr;
  uvm_reg_field fcr;
  uvm_reg_field rsv;

  function new(string name = "dbg2");
   super.new(name, 32); 
  endfunction

  virtual function void build();
    tx_fsm = fld("tx_fsm", 3,  0, "RO", 1, 3'h0);
    tx_cnt = fld("tx_cnt", 5,  3, "RO", 1, 5'h00);
    rx_fsm = fld("rx_fsm", 4,  8, "RO", 1, 4'h0);
    rx_cnt = fld("rx_cnt", 5, 12, "RO", 1, 5'h00);
    mcr    = fld("mcr",    5, 17, "RO", 1, 5'h00);
    fcr    = fld("fcr",    2, 22, "RO", 1, 2'b11);
    rsv    = fld("rsv",    8, 24, "RO", 0, 8'h00);
  endfunction
endclass : uart_reg_dbg2

// Bloque de registros
class uart_reg_block extends uvm_reg_block;
  `uvm_object_utils(uart_reg_block)

  rand uart_reg_rbr  rbr;
  rand uart_reg_thr  thr;
  rand uart_reg_ier  ier;
  rand uart_reg_iir  iir;
  rand uart_reg_fcr  fcr;
  rand uart_reg_lcr  lcr;
  rand uart_reg_mcr  mcr;
  rand uart_reg_lsr  lsr;
  rand uart_reg_msr  msr;
  rand uart_reg_byte scr;
  rand uart_reg_byte dll;
  rand uart_reg_byte dlm;
  rand uart_reg_dbg1 dbg1;
  rand uart_reg_dbg2 dbg2;

  uvm_reg_map dlab0_map;   // DLAB = 0, RBR/THR en 0 e IER en 1
  uvm_reg_map dlab1_map;   // DLAB = 1, DLL en 0 y DLM en 1

  // Constructor
  function new(string name = "uart_reg_block");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  // Crea los registros, los dos mapas y las rutas de puerta trasera
  virtual function void build();
    uvm_reg_map maps[2];   // los dos mapas, para agregar el resto de registros
    rbr  = uart_reg_rbr ::type_id::create("rbr");    // factory
    thr  = uart_reg_thr ::type_id::create("thr");
    ier  = uart_reg_ier ::type_id::create("ier");
    iir  = uart_reg_iir ::type_id::create("iir");
    fcr  = uart_reg_fcr ::type_id::create("fcr");
    lcr  = uart_reg_lcr ::type_id::create("lcr");
    mcr  = uart_reg_mcr ::type_id::create("mcr");
    lsr  = uart_reg_lsr ::type_id::create("lsr");
    msr  = uart_reg_msr ::type_id::create("msr");
    scr  = uart_reg_byte::type_id::create("scr");
    dll  = uart_reg_byte::type_id::create("dll");
    dlm  = uart_reg_byte::type_id::create("dlm");
    dbg1 = uart_reg_dbg1::type_id::create("dbg1");
    dbg2 = uart_reg_dbg2::type_id::create("dbg2");

    rbr.configure(this);  rbr.build();
    thr.configure(this);  thr.build();
    ier.configure(this);  ier.build();
    iir.configure(this);  iir.build();
    fcr.configure(this);  fcr.build();
    lcr.configure(this);  lcr.build();
    mcr.configure(this);  mcr.build();
    lsr.configure(this);  lsr.build();
    msr.configure(this);  msr.build();
    scr.configure(this);  scr.build();
    dll.configure(this);  dll.build();
    dlm.configure(this);  dlm.build();
    dbg1.configure(this); dbg1.build();
    dbg2.configure(this); dbg2.build();

    // Mapas
    dlab0_map = create_map("dlab0_map", 'h0, 4, UVM_LITTLE_ENDIAN, 1); // mapa 0
    dlab1_map = create_map("dlab1_map", 'h0, 4, UVM_LITTLE_ENDIAN, 1); // mapa 1
    default_map = dlab0_map;  // Por defaul se usa el 0
    maps = '{dlab0_map, dlab1_map};

    // DLAB = 0 
    dlab0_map.add_reg(rbr, 'h0, "RO");
    dlab0_map.add_reg(thr, 'h0, "WO");
    dlab0_map.add_reg(ier, 'h1, "RW");
    
    // DLAB = 1
    dlab1_map.add_reg(dll, 'h0, "RW");
    dlab1_map.add_reg(dlm, 'h1, "RW");

    // el resto está en los dos mapas
    foreach (maps[i]) begin
      maps[i].add_reg(iir,  'h2, "RO");
      maps[i].add_reg(fcr,  'h2, "WO");
      maps[i].add_reg(lcr,  'h3, "RW");
      maps[i].add_reg(mcr,  'h4, "WO");
      maps[i].add_reg(lsr,  'h5, "RO");
      maps[i].add_reg(msr,  'h6, "RO");
      maps[i].add_reg(scr,  'h7, "RW");
      maps[i].add_reg(dbg1, 'h8, "RO");
      maps[i].add_reg(dbg2, 'hC, "RO");
    end

    // Puerta trasera 
    add_hdl_path("tb_top.dut.regs");
    ier.add_hdl_path_slice("ier", 0, 4);
    iir.add_hdl_path_slice("iir", 0, 4);
    fcr.add_hdl_path_slice("fcr", 6, 2);   // solo los bits 7:6
    lcr.add_hdl_path_slice("lcr", 0, 8);
    mcr.add_hdl_path_slice("mcr", 0, 5);
    lsr.add_hdl_path_slice("lsr", 0, 8);
    msr.add_hdl_path_slice("msr", 0, 8);
    scr.add_hdl_path_slice("scratch", 0, 8);
    dll.add_hdl_path_slice("dl[7:0]", 0, 8);
    dlm.add_hdl_path_slice("dl[15:8]", 0, 8);

    lock_model();
  endfunction

  function void set_test_exclusions();
    uvm_reg excl[5] = '{mcr, lsr, msr, iir, fcr};   // sin bit bash ni access

    // Datos de fifos que deberia revisar el scoreboard
    uvm_resource_db#(bit)::set({"REG::", rbr.get_full_name()}, "NO_REG_TESTS", 1);
    uvm_resource_db#(bit)::set({"REG::", thr.get_full_name()}, "NO_REG_TESTS", 1);

    // MCR
    foreach (excl[i]) begin
      uvm_resource_db#(bit)::set({"REG::", excl[i].get_full_name()}, "NO_REG_BIT_BASH_TEST", 1);
      uvm_resource_db#(bit)::set({"REG::", excl[i].get_full_name()}, "NO_REG_ACCESS_TEST", 1);
    end
    // FCR no se puede leer (la dir 2 en lectura es IIR), la prueba de reset tiene que saltarlo
    uvm_resource_db#(bit)::set({"REG::", fcr.get_full_name()}, "NO_REG_HW_RESET_TEST", 1);
    

    // Debug: solo lectura
    uvm_resource_db#(bit)::set({"REG::", dbg1.get_full_name()}, "NO_REG_BIT_BASH_TEST", 1);
    uvm_resource_db#(bit)::set({"REG::", dbg2.get_full_name()}, "NO_REG_BIT_BASH_TEST", 1);
  endfunction
  
endclass : uart_reg_block

// Adaptador
class uart_reg_adapter extends uvm_reg_adapter;
  `uvm_object_utils(uart_reg_adapter)

  // Constructor
  function new(string name = "uart_reg_adapter");
    super.new(name);
    supports_byte_enable = 0;   // el sel lo arma set_reg_access
  endfunction

  // Modelo -> bus: set_reg_access pone adr, sel y el carril del dato
  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    wb_item item = wb_item::type_id::create("ral_item");   // crea el objeto con la factory
    item.set_reg_access(int'(rw.addr), (rw.kind == UVM_WRITE), rw.data[7:0]);
    return item;
  endfunction

  // Bus 
  virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    wb_item      item;
    bit [4:0]    idx;
    if (!$cast(item, bus_item)) begin
      `uvm_fatal("ADAPTER", "bus2reg recibió un item que no es wb_item")   // error fatal
      return;
    end
    idx        = uart_reg_of(item.adr, item.sel);   // registro que el DUT realmente accede
    rw.kind    = item.we ? UVM_WRITE : UVM_READ;
    rw.addr    = idx;
    rw.n_bits  = (idx >= 8) ? 32 : 8;
    rw.byte_en = '1;
    rw.status  = UVM_IS_OK;
    if (idx >= 8)     rw.data = item.we ? item.dat : item.dat_rd;   // Debug: 32 bits
    else if (item.we) rw.data = {24'h0, uart_lane8(item.sel, item.dat)};
    else              rw.data = {24'h0, uart_lane8(item.sel, item.dat_rd)};
  endfunction
endclass : uart_reg_adapter

// Predictor
class uart_reg_predictor extends uvm_reg_predictor #(wb_item);
  `uvm_component_utils(uart_reg_predictor)

  uart_reg_block regm;   // lo asigna uart_env

  // Constructor
  function new(string name = "predictor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // Elige el mapa según DLAB en el espejo y predice
  virtual function void write(wb_item tr);
    if (!tr.we && tr.is_bad_sel()) return;
    if (regm != null)
      map = regm.lcr.dlab.get_mirrored_value() ? regm.dlab1_map : regm.dlab0_map;
    super.write(tr);
  endfunction
endclass : uart_reg_predictor
