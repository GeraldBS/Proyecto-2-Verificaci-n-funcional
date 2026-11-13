//////////////////////////////////////////////////////////////////////
// uart_types: tipos y constantes que usa todo el ambiente          //
//////////////////////////////////////////////////////////////////////
// Los enums viven aquí y no en cada componente para que el driver
// serie, las secuencias, el scoreboard y la cobertura hablen igual.
//////////////////////////////////////////////////////////////////////

// Modo de paridad. Lo aleatorizamos como enum y de ahí sacamos
// PEN, EPS y SP de LCR (tabla de uart_transmitter.v):
//   {EPS,SP} = 00 impar, 10 par, 01 stick 1, 11 stick 0
typedef enum bit [2:0] {
  PAR_NONE,
  PAR_ODD,
  PAR_EVEN,
  PAR_STICK1,
  PAR_STICK0
} uart_par_e;

// Error que el agente serie mete en un carácter de recepción.
// El monitor de srx usa el mismo enum para decir qué midió en la línea.
typedef enum bit [3:0] {
  SER_OK,
  SER_PARITY,       // bit de paridad invertido
  SER_FRAME,        // primer bit de parada en 0
  SER_BREAK,        // línea en 0 por más de un carácter
  SER_GLITCH,       // pulso en 0 aislado, sin carácter
  SER_BAUD_IN,      // velocidad desviada dentro de tolerancia
  SER_BAUD_OUT,     // velocidad desviada fuera de tolerancia
  SER_GLITCH_START  // solo del monitor: el glitch provocó un falso inicio
} uart_ser_err_e;

typedef enum bit {SER_DIR_TX, SER_DIR_RX} uart_ser_dir_e;

// Forma en que el "software" atiende al UART.
typedef enum bit {SW_IRQ, SW_POLL} uart_sw_mode_e;

// Índices de registro tal como los da la especificación (wb_adr_i[4:0]).
localparam bit [4:0] UART_RBR = 5'd0;  // lectura, DLAB = 0
localparam bit [4:0] UART_THR = 5'd0;  // escritura, DLAB = 0
localparam bit [4:0] UART_DLL = 5'd0;  // DLAB = 1
localparam bit [4:0] UART_IER = 5'd1;  // DLAB = 0
localparam bit [4:0] UART_DLM = 5'd1;  // DLAB = 1
localparam bit [4:0] UART_IIR = 5'd2;  // lectura
localparam bit [4:0] UART_FCR = 5'd2;  // escritura
localparam bit [4:0] UART_LCR = 5'd3;
localparam bit [4:0] UART_MCR = 5'd4;
localparam bit [4:0] UART_LSR = 5'd5;
localparam bit [4:0] UART_MSR = 5'd6;
localparam bit [4:0] UART_SCR = 5'd7;
localparam bit [4:0] UART_DBG1 = 5'd8;
localparam bit [4:0] UART_DBG2 = 5'd12;

// Periodo del reloj de tb_top en ns (50 MHz). Lo usamos para pasar
// tiempos de carácter a tiempo de simulación.
localparam real UART_CLK_NS = 20.0;
