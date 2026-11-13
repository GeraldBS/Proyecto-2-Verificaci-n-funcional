//////////////////////////////////////////////////////////////////////////////////
// wb_item.sv Copia todos los campos de otro wb_item (la usan copy() y clone())
// function void do_copy
//////////////////////////////////////////////////////////////////////////////////

typedef enum int {SEL_NONE = 0, SEL_ONE, SEL_ALL, SEL_MULTI} wb_sel_kind_e;

class wb_item extends uvm_sequence_item;
  `uvm_object_utils(wb_item)   // registra en factory

  // bus 
  rand bit [`UART_ADDR_WIDTH-1:0] adr;   // dirección = índice del registro
  rand bit [`UART_DATA_WIDTH-1:0] dat;      // dato de escritura (en su carril)
  rand bit [3:0]                  sel;   // selección de byte (carril del dato)
  rand bit                        we;       // 1 = escritura, 0 = lectura

  // Resultado (lo llena el driver o el monitor) 
  bit [`UART_DATA_WIDTH-1:0] dat_rd;        // dato leído (wb_dat_o con el ack)
  bit                        aborted;       
  bit                        timeout;       // no llegó ack a tiempo
  bit                        sel_injected;  // el driver cambió sel por uno inválido
  realtime                   t_start;   // empieza el acceso
  realtime                   t_end;   // termina el acceso

  // Controles para el driver 
  int unsigned gap       = '1;              // ciclos de pausa antes del acceso
  int unsigned stb_delay = '1;              // ciclos que stb se retrasa respecto a cyc
  bit          bad_sel_ok = 0;

  // Constructor
  function new(string name = "wb_item");
    super.new(name);
  endfunction

  function bit gap_is_auto();       
    return (gap == '1);       
  endfunction

  function bit stb_delay_is_auto();
    return (stb_delay == '1);
  endfunction

  // Clasificación de sel 
  function wb_sel_kind_e sel_kind();
    case ($countones(sel))
      0:       return SEL_NONE;
      1:       return SEL_ONE;
      default: return (sel == 4'b1111) ? SEL_ALL : SEL_MULTI;
    endcase
  endfunction

  // Dirección de un registro Debug 
  function bit is_debug_adr();
    return (adr[4:2] == 3'd2) || (adr[4:2] == 3'd3);
  endfunction

  // sel inválido 
  function bit is_bad_sel();
    if (sel_kind() == SEL_ONE) return 0;
    if (sel == 4'b1111 && is_debug_adr()) return 0;
    return 1;
  endfunction


  // Registro que el DUT realmente accede (lo que decide wb_sel_i y adr)
  function bit [4:0] eff_reg();
    bit [1:0] lane;
    case (sel)
      4'b1000: lane = 2'd0;
      4'b0100: lane = 2'd1;
      4'b0010: lane = 2'd2;
      4'b0001: lane = 2'd3;
      default: lane = 2'd0;   // sel inválido: el DUT usa el registro {adr[4:2], 0}
    endcase
    return {adr[4:2], lane};
  endfunction

  // Llena adr, sel, dat y we para acceder al registro idx
  function void set_reg_access(int idx, bit is_write, bit [7:0] wr8 = 8'h00);
    adr = idx[`UART_ADDR_WIDTH-1:0];
    we  = is_write;
    if (idx >= 8) begin
      sel = 4'b1111;
      dat = {24'h0, wr8};
    end
    else begin
      sel = 4'b1000 >> idx[1:0];
      dat = '0;
      case (idx[1:0])
        2'd0: dat[31:24] = wr8;
        2'd1: dat[23:16] = wr8;
        2'd2: dat[15:8]  = wr8;
        2'd3: dat[7:0]   = wr8;
      endcase
    end
  endfunction

  function void do_copy(uvm_object rhs);
    wb_item r;
    super.do_copy(rhs);
    if (!$cast(r, rhs)) `uvm_fatal("WB_ITEM", "do_copy: el objeto no es un wb_item")   // error 
    adr = r.adr;  dat = r.dat;  sel = r.sel;  we = r.we;
    dat_rd = r.dat_rd;  aborted = r.aborted;  timeout = r.timeout;
    sel_injected = r.sel_injected;  t_start = r.t_start;  t_end = r.t_end;
    gap = r.gap;  stb_delay = r.stb_delay;  bad_sel_ok = r.bad_sel_ok;
  endfunction

  // Texto de una línea para los mensajes del log
  function string convert2string();
    return $sformatf("%s adr=0x%02h sel=%04b dat=0x%08h rd=0x%08h%s%s%s",
                     we ? "WR" : "RD", adr, sel, dat, dat_rd,
                     sel_injected ? " [sel inyectado]" : "",
                     aborted      ? " [abortado por reset]" : "",
                     timeout      ? " [TIMEOUT]" : "");
  endfunction

endclass : wb_item
