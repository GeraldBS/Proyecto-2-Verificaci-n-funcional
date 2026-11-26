package ral_smoke_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import wb_smoke_pkg::*;

  `include "register_model/uart_ral.sv"
  `include "wil_smokes/ral_smoke_test.sv"
endpackage : ral_smoke_pkg