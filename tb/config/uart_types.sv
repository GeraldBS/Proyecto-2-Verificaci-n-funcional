///////////////////////////////////////////////////////////////
// uart_types:
// Tipos y constantes de todo el ambiente, además de enums para
// que todos los componentes (driver serie, secuencias, scoreboard
// y cobertura) hablen el mismo idioma.
///////////////////////////////////////////////////////////////

// Dirección de un registro (5 bits con el bus de 32 bits).
typedef bit [`UART_ADDR_WIDTH-1:0] uart_adr_t;

// Modo de paridad (los 5 modos que se pueden programar en LCR).
typedef enum bit [2:0] {
  PAR_NONE,
  PAR_ODD,
  PAR_EVEN,
  PAR_STICK1,
  PAR_STICK0
} uart_par_e;

// Error que inyecta el driver serie o que mide un monitor.
typedef enum bit [3:0] {
  SER_OK,           // sin error, es el valor con el que nace un ser_item
  SER_PARITY,       // bit de paridad invertido
  SER_FRAME,        // primer bit de parada en 0
  SER_BREAK,        // línea en 0 por más de un carácter
  SER_GLITCH,       // pulso en 0 aislado, sin carácter
  SER_BAUD_IN,      // velocidad desviada dentro de tolerancia
  SER_BAUD_OUT,     // velocidad desviada fuera de tolerancia
  SER_GLITCH_START  // solo del monitor: el glitch provocó un falso inicio
} uart_ser_err_e;

// Sentido de un carácter en la línea serie: TX sale por stx, RX entra por srx.
typedef enum bit {
  SER_DIR_TX,
  SER_DIR_RX
} uart_ser_dir_e;

// Forma en que el "software" atiende al UART: por interrupciones o por sondeo.
typedef enum bit {
  SW_IRQ,
  SW_POLL
} uart_sw_mode_e;

// Identificador de la interrupción que muestra IIR[3:0] (el 0 de IIR[0] significa "hay una pendiente").
typedef enum bit [3:0] {
  IIR_MODEM   = 4'h0,   // cambio en las líneas del módem
  IIR_NONE    = 4'h1,   // ninguna interrupción pendiente
  IIR_THRE    = 4'h2,   // FIFO de TX vacía
  IIR_RDA     = 4'h4,   // dato recibido (nivel de disparo)
  IIR_RLS     = 4'h6,   // estado de línea (paridad, trama, break, overrun)
  IIR_TIMEOUT = 4'hC    // tiempo de espera de la FIFO RX
} uart_iir_id_e;

// Le colocamos nombres a registros y establecemos un orden, son de 5 bits porque con el bus de 32 bits la dirección tiene 5 bits.
localparam uart_adr_t UART_RBR = 'd0;   // lectura, DLAB = 0
localparam uart_adr_t UART_THR = 'd0;   // escritura, DLAB = 0
localparam uart_adr_t UART_DLL = 'd0;   // DLAB = 1
localparam uart_adr_t UART_IER = 'd1;   // DLAB = 0
localparam uart_adr_t UART_DLM = 'd1;   // DLAB = 1
localparam uart_adr_t UART_IIR = 'd2;   // Qué interrupción hay
localparam uart_adr_t UART_FCR = 'd2;   // Control de las FIFO
localparam uart_adr_t UART_LCR = 'd3;   // Longitud, paradas, paridad, break y DLAB
localparam uart_adr_t UART_MCR = 'd4;   // DTR, RTS, OUT1, OUT2 y loopback
localparam uart_adr_t UART_LSR = 'd5;   // estado de línea
localparam uart_adr_t UART_MSR = 'd6;   // estado del módem
localparam uart_adr_t UART_SCR = 'd7;   // Guarda lo que se escribe
localparam uart_adr_t UART_DBG1 = 'd8;  // depuración 1
localparam uart_adr_t UART_DBG2 = 'd12; // depuración 2

// Posición de cada bit en LSR
localparam int UART_LSR_DR   = 0;
localparam int UART_LSR_OE   = 1;
localparam int UART_LSR_PE   = 2;
localparam int UART_LSR_FE   = 3;
localparam int UART_LSR_BI   = 4;
localparam int UART_LSR_THRE = 5;
localparam int UART_LSR_TEMT = 6;

// Posición de cada campo en LCR.
localparam int UART_LCR_WLS  = 0;
localparam int UART_LCR_STB  = 2;
localparam int UART_LCR_PEN  = 3;
localparam int UART_LCR_EPS  = 4;
localparam int UART_LCR_SP   = 5;
localparam int UART_LCR_BRK  = 6;
localparam int UART_LCR_DLAB = 7;

// Posición de cada campo en FCR.
localparam int UART_FCR_EN    = 0;   // el DUT lo ignora
localparam int UART_FCR_RXCLR = 1;
localparam int UART_FCR_TXCLR = 2;
localparam int UART_FCR_DMA   = 3;   // el DUT lo ignora
localparam int UART_FCR_TL    = 6;   // [7:6] nivel de disparo de la FIFO RX

// Posición de cada bit en IER (bits 7:4 reservados).
localparam int UART_IER_RDA   = 0;
localparam int UART_IER_THRE  = 1;
localparam int UART_IER_RLS   = 2;
localparam int UART_IER_MS    = 3;

// Posición de cada bit en MCR (bits 7:5 reservados).
localparam int UART_MCR_DTR   = 0;
localparam int UART_MCR_RTS   = 1;
localparam int UART_MCR_OUT1  = 2;
localparam int UART_MCR_OUT2  = 3;
localparam int UART_MCR_LOOP  = 4;

// Profundidad de las FIFO de TX y RX.
localparam int UART_FIFO_DEPTH = `UART_FIFO_DEPTH;

// Registro al que llega un acceso con bus de 32 bits
function automatic uart_adr_t uart_reg_of(uart_adr_t adr, bit [3:0] sel);
  if (adr >= 8) return adr;
  case (sel)
    4'b1000: return {adr[4:2], 2'd0};
    4'b0100: return {adr[4:2], 2'd1};
    4'b0010: return {adr[4:2], 2'd2};
    4'b0001: return {adr[4:2], 2'd3};
    default: return {adr[4:2], 2'd0};
  endcase
endfunction

// Byte de un registro de 8 bits dentro de la palabra del bus.
function automatic bit [7:0] uart_lane8(bit [3:0] sel, bit [31:0] data);
  case (sel)
    4'b1000: return data[31:24];
    4'b0100: return data[23:16];
    4'b0010: return data[15:8];
    default: return data[7:0];
  endcase
endfunction

// Periodo del reloj de tb_top en ns (50 MHz). Se usa para pasar tiempos de carácter a tiempo de simulación.
localparam real UART_CLK_NS = 20.0;