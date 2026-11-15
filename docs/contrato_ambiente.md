# Contrato entre las partes del ambiente

Para que las partes encajen, cada clase que otro usa tiene que llamarse igual y tener estos campos. Lo que no aparece aquí, cada uno lo hace como quiera.

Todo va dentro de `uart_pkg` (`tb/uart_pkg.sv`), que incluye los archivos en este orden.

## Lo que ya está (Gerald)

| Archivo | Clase | Para qué |
|---|---|---|
| `tb/config/uart_types.sv` | `uart_par_e`, `uart_ser_err_e`, `uart_ser_dir_e`, `uart_sw_mode_e`, constantes `UART_LCR`, `UART_LSR`... | Tipos comunes |
| `tb/config/uart_line_cfg.sv` | `uart_line_cfg` | Formato vigente: `wls`, `stb`, `par_mode`, `dl`, `pen()`, `eps()`, `sp()`, `data_bits()`, `stop_ticks()`, `bit_cycles()`, `tc_cycles()` |
| `tb/config/uart_ctrl_cfg.sv` | `uart_ctrl_cfg` | FCR, IER y MCR vigentes: `tl`, `trigger_level()`, `ier`, `loop`, `dtr`, `rts`, `out1`, `out2` |
| `tb/config/uart_agent_cfgs.sv` | `wb_agent_cfg`, `uart_ser_agent_cfg`, `modem_agent_cfg`, `uart_scb_cfg`, `uart_cov_cfg` | Knobs e interfaz virtual (`vif`) de cada componente |
| `tb/config/uart_env_cfg.sv` | `uart_env_cfg` | Knobs de la prueba, `parse_plusargs()`, `print_knobs()` |
| `tb/sequences/uart_virtual_sequencer.sv` | `uart_virtual_sequencer` | Campos `wb_sqr`, `ser_sqr`, `mdm_sqr`, `regm`, `cfg` |
| `tests/uart_base_test.sv` | `uart_base_test` | La prueba |

Los objetos de configuración están solo en `tb/config/` (no dentro de `uart_pkg.sv`). Los knobs de `wb_agent_cfg` se llaman `gap_max`, `gap_zero_pct`, `stb_delay_pct`, `stb_delay_max` y `bad_sel_pct`; los de `uart_ser_agent_cfg` y `modem_agent_cfg` están en `uart_agent_cfgs.sv`. Las constantes `UART_KEY_CFG`, `UART_PATH_*` y `UART_KEY_*_VIF` siguen en `uart_pkg.sv`.

Cada componente obtiene su objeto con `uvm_config_db#(<tipo>)::get(this, "", "cfg", cfg)`. El ambiente y el secuenciador virtual usan `"env_cfg"`.

**Formato vigente:** `cfg.ser.line`, `cfg.scb.line` y `cfg.cov.line` son la misma referencia que `cfg.line`. Cuando la secuencia reconfigura el UART, todos ven el formato nuevo sin hacer nada. Para el loopback, la secuencia pone `cfg.ser.loopback`.

## Leo: Wishbone, interrupción, RAL y ambiente

**`tb/wishbone_agent/wb_item.sv`** (el de Leo; las secuencias de Gerald usan estos campos)
```systemverilog
class wb_item extends uvm_sequence_item;
  rand bit [`UART_ADDR_WIDTH-1:0] adr;  // índice de la spec: 0..7, 8, 12
  rand bit [`UART_DATA_WIDTH-1:0] dat;  // dato a escribir, ya en su carril
  rand bit [3:0]  sel;       // carril (lo pone set_reg_access; el driver lo puede cambiar)
  rand bit        we;
  bit [`UART_DATA_WIDTH-1:0] dat_rd;   // dato leído tal como viene del bus, en su carril
  bit             aborted;   // un reset cortó la transferencia
  bit             timeout;   // no llegó el ack a tiempo
  bit             sel_injected; // el driver cambió sel por uno inválido
  int unsigned    gap, stb_delay; // '1 = que el driver decida con los knobs
  bit             bad_sel_ok;// 1: el driver puede meter un sel inválido (AMB-05)
  function void set_reg_access(int idx, bit is_write, bit [7:0] wr8 = 8'h00);
endclass
```
- Las secuencias arman cada acceso con `set_reg_access()`, que pone `adr`, `sel = 4'b1000 >> idx[1:0]` (big endian, como el TUTORIAL) y el byte en su carril. Para 8 y 12 usa `sel = 1111`.
- El **driver** decide las pausas y el retraso de `stb` con los knobs de `wb_agent_cfg` (`gap_max`, `gap_zero_pct`, `stb_delay_pct`, `stb_delay_max`). Si el item trae `bad_sel_ok = 1` y `adr < 8`, cambia `sel` por uno inválido con probabilidad `bad_sel_pct`, deja en `item.sel` el que usó y pone `sel_injected = 1`. Las secuencias solo dan permiso en lecturas y en escrituras a 0..3 con DLAB = 0 (caen en THR).
- El **monitor** publica un `wb_item` por cada transferencia con `ack`, con `dat`, `dat_rd` y `sel` tal como estaban en el bus. También publica un `wb_rst_item` cuando el reset sube y cuando baja (`asserted`, `width_cycles`, `during_access`, `is_initial`).
- Para saber qué registro y qué byte usó el DUT están `uart_reg_of(adr, sel)` y `uart_lane8(sel, dato)` en `tb/config/uart_types.sv` (hacen lo mismo que `uart_wb.v`, incluido el sel inválido). Las usan la secuencia base y la cobertura; el scoreboard debería usar las mismas.
- `uart_wb_agent` tiene `sqr` (de tipo `wb_sequencer`), `drv`, `mon` e `int_mon`, y reenvía lo de sus monitores por tres puertos propios: `ap` (accesos, `wb_item`), `rst_ap` (resets, `wb_rst_item`) e `int_ap` (flancos de `int_o`, `uart_int_item`). Los demás componentes se conectan a esos tres, no a los monitores.

**`tb/wishbone_agent/uart_int_monitor.sv`** (dentro del agente Wishbone): publica un `uart_int_item` (con `bit level` y `bit in_reset`) en cada flanco de `int_o`. Sale del agente por `int_ap`.

**`tb/register_model/uart_ral.sv`** (pendiente): `uart_reg_block` con los registros, los dos mapas `dlab0_map` y `dlab1_map`, `build()` y `set_test_exclusions()`; `uart_reg_adapter` (de `uvm_reg_bus_op` a `wb_item`) y `uart_reg_predictor`, con los campos `map`, `regm`, `adapter` y el puerto `bus_in`. La secuencia principal corre `uvm_reg_hw_reset_seq` sobre `p_sequencer.regm` al inicio.

**`tb/environment/uart_env.sv`**: `uart_env` con las instancias `wb_agt`, `ser_agt`, `mdm_agt`, `mod_reg` (el modelo de registros), `adapter`, `predictor`, `scb`, `cov` (de tipo `uart_cov`) y `vsqr` (de tipo `uart_virtual_sequencer`). En `connect_phase`, además de enganchar los dos mapas al `wb_agt.sqr` con el adaptador:
```systemverilog
wb_agt.ap.connect     (predictor.bus_in);
wb_agt.ap.connect     (scb.wb_imp);
wb_agt.rst_ap.connect (scb.rst_imp);
wb_agt.int_ap.connect (scb.int_imp);
wb_agt.ap.connect     (cov.wb_imp);
wb_agt.int_ap.connect (cov.int_imp);
ser_agt.tx_ap.connect (scb.tx_imp);
ser_agt.rx_ap.connect (scb.rx_imp);
mdm_agt.ap.connect    (scb.mdm_imp);
ser_agt.tx_ap.connect (cov.tx_imp);
ser_agt.rx_ap.connect (cov.rx_imp);
mdm_agt.ap.connect    (cov.mdm_imp);
scb.ap.connect        (cov.evt_imp);
vsqr.wb_sqr  = wb_agt.sqr;
vsqr.ser_sqr = ser_agt.sqr;
vsqr.mdm_sqr = mdm_agt.sqr;
vsqr.regm    = mod_reg;
```
La cobertura no tiene `rst_imp`. Se entera del reset por el evento `EV_RESET` que manda el scoreboard.

## Wilbert: serie, módem y scoreboard

**`tb/serial_agent/ser_item.sv`**
```systemverilog
class ser_item extends uvm_sequence_item;
  // lo llena la secuencia RX (estímulo)
  rand bit [7:0]        data;
  rand uart_ser_err_e   err;        // SER_OK, SER_PARITY, SER_FRAME, SER_BREAK, SER_GLITCH, SER_BAUD_IN, SER_BAUD_OUT
  rand int unsigned     gap_bits;   // bits en reposo antes del carácter
  rand int unsigned     glitch_w;   // ancho del glitch en dieciseisavos de bit (1..15)
  rand int              baud_dev;   // desviación de velocidad en décimas de %, con signo
  rand int unsigned     break_bits; // duración del break en bits
  rand bit              short_stop; // mandar 1 solo bit de parada aunque LCR pida 1.5 o 2
  // lo llenan los monitores
  uart_ser_dir_e        dir;        // SER_DIR_TX (stx) o SER_DIR_RX (srx)
endclass
```
- El **driver** toma el formato de `cfg.line` y manda el carácter por `srx` con el error pedido.
- El **monitor de srx** pone en `err` lo que midió en la línea, no lo que pidió la secuencia.
- `uart_ser_agent` tiene `sqr` (`uvm_sequencer #(ser_item)`), `tx_ap` (monitor de stx) y `rx_ap` (monitor de srx).

**`tb/modem_agent/mdm_item.sv`**
```systemverilog
class mdm_item extends uvm_sequence_item;
  rand bit [3:0]    toggle;      // qué entradas invertir: bit 0 CTS, 1 DSR, 2 RI, 3 DCD
  rand int unsigned gap_cycles;  // ciclos de espera antes del cambio
  // lo llena el monitor
  bit [3:0]         in_val;      // CTS, DSR, RI, DCD después del cambio
  bit [3:0]         in_chg;      // cuáles cambiaron
  bit               rts, dtr;
endclass
```
`modem_agent` tiene `sqr` (`uvm_sequencer #(mdm_item)`) y su propio `ap`, que reenvía lo del monitor (igual que el agente Wishbone).

**`tb/scoreboard/uart_scoreboard.sv`**: `uart_scoreboard` recibe por `wb_imp` (`wb_item`), `rst_imp` (`wb_rst_item`), `int_imp` (`uart_int_item`), `tx_imp` y `rx_imp` (`ser_item`) y `mdm_imp` (`mdm_item`). Así lo conecta el ambiente de Leo.

**`tb/scoreboard/uart_model_evt.sv`**: eventos del modelo para la cobertura, por `scb.ap`:
```systemverilog
typedef enum {EV_THR_WRITE, EV_RX_PUSH, EV_RBR_READ, EV_RESET} uart_evt_e;
class uart_model_evt extends uvm_object;
  uart_evt_e   kind;
  int unsigned tx_level;     // nivel de la FIFO TX antes de la escritura
  int unsigned rx_level;     // nivel de la FIFO RX antes de empujar o leer
  bit          lost;         // escritura perdida (TX llena) u overrun (RX llena)
  int unsigned pending_cnt;  // fuentes de interrupción pendientes
  bit          tx_busy, rx_busy;
  int unsigned rst_cycles;   // solo EV_RESET
endclass
```

## Cosas que las secuencias suponen

- **Reset en medio:** la secuencia de eventos sube `wb_vif.rst` en cualquier momento, incluso en medio de una transferencia. Si eso pasa, el driver Wishbone tiene que bajar `cyc` y `stb` y hacer `item_done` sin esperar el `ack`. Si no, la secuencia se queda trabada.
- **El modelo sigue al bus, no a los objetos de configuración:** el ruido de registros escribe IER, THR y el scratch, y a veces lee con DLAB = 1. El scoreboard tiene que tomar lo que ve el monitor Wishbone, no `uart_ctrl_cfg`.
- **El monitor de stx** reporta un break en TX como un `ser_item` con `err = SER_BREAK` y `dir = SER_DIR_TX`.
- **El monitor de srx** pone `short_stop = 1` si midió un solo bit de parada con LCR[2] = 1.
- **Loopback:** con `cfg.ser.loopback = 1` la secuencia no manda caracteres por srx. El driver debe dejar la línea en reposo.
- **Fin de cada episodio:** la secuencia dispara el evento global `uart_ep_end` (`uvm_event_pool::get_global("uart_ep_end")`). Lo usa la cobertura y lo puede usar quien lo necesite.

## Orden de `tb/uart_pkg.sv`

1. Constantes de `uvm_config_db` y `config/` (Gerald)
2. `wishbone_agent/` (Leo): `wb_item`, `wb_events` (con `uart_int_item`), driver, secuenciador, monitor, `uart_int_monitor`, agente y secuencias
3. `serial_agent/` y `modem_agent/` (Wilbert): primero el item y después el agente
4. `register_model/uart_ral.sv` (Leo)
5. `scoreboard/uart_model_evt.sv` y `scoreboard/uart_scoreboard.sv` (Wilbert)
6. `coverage/uart_cov.sv` y `sequences/` (Gerald)
7. `environment/uart_env.sv` (Leo)
8. `uart_base_test.sv` (está en `tests/`, por eso `filelist.f` tiene `+incdir+../tests`)

Si alguien cambia el nombre de un archivo, lo cambia también en `uart_pkg.sv`.
