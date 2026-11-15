//////////////////////////////////////////////////////////////////////
// uart_seqs: todas las secuencias, en orden de dependencia         //
//////////////////////////////////////////////////////////////////////
`include "sequences/uart_base_vseq.sv"
`include "sequences/uart_program_vseq.sv"
`include "sequences/uart_tx_vseq.sv"
`include "sequences/uart_rx_vseq.sv"
`include "sequences/uart_mdm_vseq.sv"
`include "sequences/uart_sw_vseq.sv"
`include "sequences/uart_events_vseq.sv"
`include "sequences/uart_main_vseq.sv"
