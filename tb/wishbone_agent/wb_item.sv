//////////////////////////////////////////////////////////////////////////////////
// wb_item.sv
//////////////////////////////////////////////////////////////////////////////////

// Índices de registro de la especificación (adr = índice, ver arriba)
localparam int REG_RBR  = 0;   // lectura  (DLAB = 0)
localparam int REG_THR  = 0;   // escritura (DLAB = 0)
localparam int REG_DLL  = 0;   // DLAB = 1
localparam int REG_IER  = 1;   // DLAB = 0
localparam int REG_DLM  = 1;   // DLAB = 1
localparam int REG_IIR  = 2;   // lectura
localparam int REG_FCR  = 2;   // escritura
localparam int REG_LCR  = 3;
localparam int REG_MCR  = 4;
localparam int REG_LSR  = 5;
localparam int REG_MSR  = 6;
localparam int REG_SCR  = 7;   // scratch (AMB-01)
localparam int REG_DBG1 = 8;   // Debug 1 (32 bits, sel = 1111)
localparam int REG_DBG2 = 12;  // Debug 2 (32 bits, sel = 1111)

// Clasificación de wb_sel_i (coincide con los bins de cg_reg_access.cp_sel)
typedef enum int {SEL_NONE = 0, SEL_ONE, SEL_ALL, SEL_MULTI} wb_sel_kind_e;

// Un acceso Wishbone: dirección, selección de byte, dato y resultado
class wb_item extends uvm_sequence_item;
  `uvm_object_utils(wb_item)   // macro de UVM: registra la clase en la factory

  // bus 
  rand bit [`UART_ADDR_WIDTH-1:0] adr;   // dirección = índice del registro
  rand bit [`UART_DATA_WIDTH-1:0] dat;      // dato de escritura (en su carril)
  rand bit [3:0]                  sel;   // selección de byte (carril del dato)
  rand bit                        we;       // 1 = escritura, 0 = lectura

  // Resultado (lo llena el driver o el monitor) 
  bit [`UART_DATA_WIDTH-1:0] dat_rd;        // dato leído (wb_dat_o con el ack)
  bit                        aborted;       // un reset cortó la transferencia
  bit                        timeout;       // no llegó ack a tiempo
  bit                        sel_injected;  // el driver cambió sel por uno inválido
  realtime                   t_start;   // instante en que empieza el acceso
  realtime                   t_end;   // instante en que termina el acceso

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

endclass : wb_item
