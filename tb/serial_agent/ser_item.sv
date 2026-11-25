

class ser_item extends uvm_sequence_item;

    rand bit [7:0]        data;         // Dato a enviar
    rand uart_ser_err_e   err;          // error que se mete a la trama
    rand int unsigned     gap_bits;     // Tiempo de reposo (en bits) antes del carácter
    rand int unsigned     glitch_w;     // Ancho del glitch (en 1/16 de bit)
    rand int              baud_dev;     // Desviación en la tasa de baudios (décimas de %)
    rand int unsigned     break_bits;   // Duración de la condición de break (en bits)
    rand bit              short_stop;   // Fuerza enviar 1 bit de parada aunque LCR pida más

    uart_ser_dir_e dir;          // Dirección: SER_DIR_TX o SER_DIR_RX

    //UVM Factory register (macros necesarios para automatización)

    `uvm_object_utils_begin(ser_item)
    `uvm_field_int (data,       UVM_ALL_ON)
    `uvm_field_enum(uart_ser_err_e, err, UVM_ALL_ON)
    `uvm_field_int (gap_bits,   UVM_ALL_ON | UVM_DEC)
    `uvm_field_int (glitch_w,   UVM_ALL_ON | UVM_DEC)
    `uvm_field_int (baud_dev,   UVM_ALL_ON | UVM_DEC)
    `uvm_field_int (break_bits, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int (short_stop, UVM_ALL_ON)
    `uvm_field_enum(uart_ser_dir_e, dir, UVM_ALL_ON)
  `uvm_object_utils_end

    // Constructor
    function new(string name = "ser_item");
        super.new(name);
    endfunction

    //Restricciones para proteger limites fisicos 

    constraint c_glitch_width {glitch_w inside {[1:15]};};

endclass : ser_item
