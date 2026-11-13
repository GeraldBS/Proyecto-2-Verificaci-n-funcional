//////////////////////////////////////////////////////////////////////////////////
// wb_events.sv
// Eventos que publica el agente Wishbone además de los accesos
//////////////////////////////////////////////////////////////////////////////////

class wb_rst_item extends uvm_sequence_item;
  `uvm_object_utils(wb_rst_item)   // factory

  bit          asserted;        // 1 = el reset acaba de subir, 0 = acaba de bajar
  int unsigned width_cycles;    // ciclos de reloj con el reset activo (válido al bajar)
  bit          during_access;   // había una transferencia en curso (cyc y stb) al subir
  bit          is_initial;      // es el reset del arranque de la simulación
  realtime     t;               // instante del evento

  // Constructor
  function new(string name = "wb_rst_item");
    super.new(name);
  endfunction

  // Texto de una línea para los mensajes del log
  function string convert2string();
    return $sformatf("RST %s ancho=%0d ciclos%s%s",
                     asserted ? "sube" : "baja", width_cycles,
                     during_access ? " durante un acceso" : "",
                     is_initial    ? " inicial" : "");
  endfunction
endclass : wb_rst_item

// Flanco de int_o
class uart_int_item extends uvm_sequence_item;
  `uvm_object_utils(uart_int_item)   // factory

  bit      level;      // valor nuevo de int_o: 1 = sube, 0 = baja
  bit      in_reset;   // el flanco ocurrió con el reset activo
  realtime t;          // instante del flanco

  // Constructor
  function new(string name = "uart_int_item");
    super.new(name);
  endfunction

  // Texto de una línea para los mensajes del log
  function string convert2string();
    return $sformatf("INT %s%s", level ? "sube" : "baja", in_reset ? " [en reset]" : "");
  endfunction
endclass : uart_int_item
