
//
`uvm_analysis_imp_decl(_wb)
`uvm_analysis_imp_decl(_rst)
`uvm_analysis_imp_decl(_int)
`uvm_analysis_imp_decl(_tx)
`uvm_analysis_imp_decl(_rx)
`uvm_analysis_imp_decl(_mdm)

class uart_scoreboard extends uvm_scoreboard;
    // Registro en la Factory
  `uvm_component_utils(uart_scoreboard)

  uart_scb_cfg cfg;

  bit [7:0] tx_fifo[$];      // Emulación de la FIFO de transmisión
  bit [7:0] rx_fifo[$];      // Emulación de la FIFO de recepción
  
  bit [7:0] exp_lsr;         // Estado esperado del Line Status Register
  bit [7:0] exp_iir;         // Estado esperado del Interrupt Identification Register
  bit [7:0] exp_msr;         // Estado esperado del Modem Status Register
  
  bit       dlab_bit;        // Rastreo del bit DLAB para resolver direcciones
  int       error_count;

  // Puertos TLM
  uvm_analysis_imp_wb  #(wb_item, uart_scoreboard)       wb_imp;
  uvm_analysis_imp_rst #(wb_rst_item, uart_scoreboard)   rst_imp;
  uvm_analysis_imp_int #(uart_int_item, uart_scoreboard) int_imp;
  uvm_analysis_imp_tx  #(ser_item, uart_scoreboard)      tx_imp;
  uvm_analysis_imp_rx  #(ser_item, uart_scoreboard)      rx_imp;
  uvm_analysis_imp_mdm #(mdm_item, uart_scoreboard)      mdm_imp;
  uvm_analysis_port    #(uart_model_evt)                 ap;

  function new(string name = "uart_scoreboard", uvm_component parent);
    super.new(name, parent);
  endfunction

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
  endfunction

  // Manejo del Reset
 
  virtual function void write_rst(wb_rst_item item);
    uart_model_evt evt;

    if (item.asserted) begin
      // Limpiar FIFOs y restaurar valores por defecto según especificación
      tx_fifo.delete();
      rx_fifo.delete();
      exp_lsr  = 8'h60; // THRE y TEMT en 1 (transmisor vacío)
      exp_iir  = 8'hC1; // Sin interrupciones pendientes
      exp_msr  = 8'h00;
      dlab_bit = 1'b0;

      // Notificar a la cobertura funcional que ocurrió un reset
      evt = uart_model_evt::type_id::create("evt");
      evt.kind = EV_RESET;
      evt.rst_cycles = item.width_cycles;
      ap.write(evt);
    end
  endfunction

  // 2. Manejo del Bus Wishbone (CPU accediendo a registros)

  virtual function void write_wb(wb_item item);
    uart_model_evt evt;
    bit [7:0] dat8;

    // Ignorar accesos abortados o sin acuse (ack)
    if (!item.ack || item.aborted) return; 

    // Extraer el byte válido según el carril 
    dat8 = uart_lane8(item.sel, item.dat);

    // Rastrear el bit DLAB (Bit 7 de LCR, Dirección 3)
    if (item.we && item.adr == 3) begin
      dlab_bit = dat8[7];
    end

    if (item.we) begin
      // ESCRITURA EN THR (Dirección 0, DLAB = 0)
      if (item.adr == 0 && dlab_bit == 0) begin
        evt = uart_model_evt::type_id::create("evt");
        evt.kind     = EV_THR_WRITE;
        evt.tx_level = tx_fifo.size();

        if (tx_fifo.size() < 16) begin
          tx_fifo.push_back(dat8);
          evt.lost = 0;
          exp_lsr[5] = 0; // THRE baja porque la FIFO ya no está vacía
        end else begin
          evt.lost = 1;   // Transacción perdida por FIFO llena
        end
        ap.write(evt);
      end
    end 
    else begin
      // LECTURA DE RBR (Dirección 0, DLAB = 0)
      if (item.adr == 0 && dlab_bit == 0) begin
        evt = uart_model_evt::type_id::create("evt");
        evt.kind     = EV_RBR_READ;
        evt.rx_level = rx_fifo.size();

        if (rx_fifo.size() > 0) begin
          rx_fifo.pop_front();
        end
        
        // Si la FIFO de recepción queda vacía, apagar DR (Data Ready) en LSR
        if (rx_fifo.size() == 0) begin
          exp_lsr[0] = 0;
        end
        
        evt.lost = 0;
        ap.write(evt);
      end
    end
  endfunction

  // (Las funciones write_tx, write_rx, write_mdm y write_int se mantienen vacías por ahora)
  virtual function void write_int(uart_int_item item); endfunction
  virtual function void write_tx(ser_item item); endfunction
  virtual function void write_rx(ser_item item); endfunction
  virtual function void write_mdm(mdm_item item); endfunction
endclass : uart_scoreboard

