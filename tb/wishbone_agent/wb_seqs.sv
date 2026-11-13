//////////////////////////////////////////////////////////////////////////////////
// wb_seqs.sv
// Secuencias Wishbone de bajo nivel
// Se ejecutan sobre wb_sequencer.
//////////////////////////////////////////////////////////////////////////////////

class wb_base_seq extends uvm_sequence #(wb_item);
  `uvm_object_utils(wb_base_seq)   // registra en factory
  `uvm_declare_p_sequencer(wb_sequencer)   // macro de UVM: da acceso al secuenciador como p_sequencer

  int unsigned n_acc = 0;     // accesos hechos por esta secuencia
  wb_item      last;          // último item (con dat_rd y las banderas del driver)

  // Constructor
  function new(string name = "wb_base_seq");
    super.new(name);
  endfunction

  // Escribe un registro de 8 bits
  // bad_sel_ok = 1 permite que el driver inyecte un sel inválido.
  task wb_write(int idx, bit [7:0] val, bit bad_sel_ok = 0);
    wb_item item = wb_item::type_id::create("wb_wr");   // crea el objeto con la factory
    start_item(item);   // pide turno al secuenciador
    item.set_reg_access(idx, 1'b1, val);
    item.bad_sel_ok = bad_sel_ok;
    finish_item(item);   // envía el item al driver y espera a que termine
    last = item;   // guarda el item para consultar dat_rd
    n_acc++;   // cuenta el acceso
  endtask

  // Lee un registro. val trae 8 bits para los registros 0 a 7 y 32 bits 
  task wb_read(int idx, output bit [31:0] val, input bit bad_sel_ok = 0);
    wb_item item = wb_item::type_id::create("wb_rd");   // crea el objeto con la factory
    start_item(item);   // pide turno al secuenciador
    item.set_reg_access(idx, 1'b0);
    item.bad_sel_ok = bad_sel_ok;
    finish_item(item);   // envía el item al driver y espera a que termine
    last = item;   // guarda el item para consultar dat_rd
    n_acc++;   // cuenta el acceso
    val = (idx >= 8) ? item.dat_rd : {24'h0, item.rdata8()};   // 32 bits en Debug 1 y 2, 8 bits en los demás
  endtask

  // Pausa en ciclos de reloj dentro de una secuencia
  task wb_idle(int unsigned cycles);
    repeat (cycles) @(p_sequencer.cfg.vif.drv_cb);   // espera ciclos de reloj
  endtask
endclass : wb_base_seq
