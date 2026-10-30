# Tutorial: cómo instanciar el UART 16550 en un ambiente UVM

Este tutorial explica, paso a paso, cómo conectar `uart_top` a un banco de pruebas UVM con VCS y UVM 1.2. Los archivos de `tb/` y `sim/` son un ejemplo funcional y mínimo; el ambiente completo (agentes, RAL, scoreboard, cobertura) lo construye cada grupo.

## 0. Arranque rápido

```sh
cd sim
make            # compila y corre uart_hello_test
```

Si la instancia está bien, el log `run_uart_hello_test_1.log` termina con:

```
UVM_INFO ... [HELLO] LCR = 0x03, IIR = 0x.., LSR = 0x..
UVM_INFO ... [HELLO] Instancia correcta: el DUT responde por Wishbone
...
UVM_ERROR :    0
UVM_FATAL :    0
```

Otras órdenes útiles: `make run SEED=42`, `make BUS8=1` (variante de 8 bits), `make FSDB=1` (formas de onda para Verdi), `make cov` (reporte de cobertura).

## 1. Estructura del paquete

```
uart16550_proyecto_uvm/
├── rtl/          RTL del DUT, copiado sin cambios de rtl/verilog/ del proyecto original
├── doc/          UART_spec.pdf (documento normativo) y CHANGES.txt
├── tb/
│   ├── wb_if.sv           interfaz Wishbone (incluye int_o como irq)
│   ├── uart_ser_if.sv     interfaz de la línea serie (stx, srx, baud)
│   ├── modem_if.sv        señales de módem
│   ├── uart_wb_sva.sv     ejemplo de módulo de aserciones para bind
│   ├── uart_hello_pkg.sv  prueba de humo (solo para validar la instancia)
│   └── tb_top.sv          módulo superior
└── sim/
    ├── filelist.f         orden de compilación
    └── Makefile           compilación, simulación y cobertura
```

**No modifiquen nada en `rtl/`.** Si encuentran un error del DUT, se documenta (sección 3.5 del enunciado).

## 2. Configuración de compilación

El RTL incluye dos archivos con `` `include ``: `timescale.v` y `uart_defines.v`. Por eso no aparecen en `filelist.f`, pero el compilador debe saber dónde buscarlos:

```
+incdir+../rtl
```

El ancho del bus se elige con una macro **en la línea de comandos**, nunca editando `uart_defines.v`:

| Variante | Opción de VCS | `wb_adr_i` | `wb_dat_i` / `wb_dat_o` | Registros Debug |
|---|---|---|---|---|
| 32 bits (obligatoria) | ninguna | 5 bits | 32 bits | Sí (direcciones 8 y 12) |
| 8 bits (puntos extra) | `+define+DATA_BUS_WIDTH_8` | 3 bits | 8 bits | No |

Las interfaces de `tb/` incluyen `uart_defines.v` y toman los anchos de las macros `` `UART_ADDR_WIDTH `` y `` `UART_DATA_WIDTH ``. Así, el mismo código sirve para ambas variantes; basta con recompilar con otra macro.

## 3. Interfaces

Se usa una interfaz por protocolo, porque cada una tendrá su propio agente:

| Interfaz | Señales del DUT | Agente que la usa |
|---|---|---|
| `wb_if` | `wb_*`, `int_o` | Agente Wishbone y monitor de interrupción |
| `uart_ser_if` | `stx_pad_o`, `srx_pad_i`, `baud_o` | Agente serie (driver hacia `srx`, monitores de `stx` y `srx`) |
| `modem_if` | `rts_pad_o`, `dtr_pad_o`, `cts_pad_i`, `dsr_pad_i`, `ri_pad_i`, `dcd_pad_i` | Agente de módem |

Cada interfaz tiene dos *clocking blocks*:

- `drv_cb`: el driver escribe en las salidas con un pequeño retardo después del flanco (`output #1`) y lee las respuestas justo antes del flanco (`input #1step`). Esto evita carreras entre el banco de pruebas y el RTL.
- `mon_cb`: el monitor solo lee.

En `wb_if`, los datos se nombran desde el punto de vista del bus: `dat_m2s` va del maestro (el ambiente) al esclavo (el DUT, `wb_dat_i`) y `dat_s2m` va del esclavo al maestro (`wb_dat_o`). Así no hay confusión entre los `_i` y `_o` del DUT y los del ambiente.

## 4. El módulo superior (`tb/tb_top.sv`)

El *top* hace cinco cosas, en este orden.

### 4.1 Reloj

```systemverilog
parameter real CLK_PERIOD_NS = 20.0;          // 50 MHz
logic clk = 1'b0;
always #(CLK_PERIOD_NS / 2.0) clk = ~clk;
```

La tasa de baudios es `f_clk / (16 × DL)`. Con 50 MHz y `DL = 1`, cada bit dura 16 ciclos (320 ns) y un carácter de 8N1 dura 10 bits. Valores grandes de DL alargan mucho la simulación: tómenlo en cuenta al definir los rangos de aleatorización.

### 4.2 Interfaces, reset y valores de reposo

```systemverilog
wb_if       wb  (clk);
uart_ser_if ser (clk);
modem_if    mdm (clk);

initial begin
  wb.rst  = 1'b1;
  wb.cyc  = 1'b0;  wb.stb = 1'b0;  ...
  ser.srx = 1'b1;   // ¡línea serie en reposo!
  mdm.cts = 1'b1;  ...
  repeat (5) @(posedge clk);
  wb.rst  = 1'b0;
end
```

- `wb_rst_i` es **asíncrono y activo en alto**.
- `srx` debe arrancar en 1. Si queda en X o en 0, el receptor detecta bits de inicio falsos desde el primer ciclo.
- Las entradas de módem necesitan un valor definido. El valor de reposo correcto depende de la polaridad, que es uno de los puntos de la sección 3.5 que deben aclarar.
- Si su plan incluye reset aleatorio, el manejo de `wb.rst` debe pasar a un componente del ambiente; eliminen entonces el reset del `initial`.

### 4.3 Instancia del DUT

Siempre con conexiones **por nombre**:

```systemverilog
uart_top dut (
  .wb_clk_i  (clk),
  .wb_rst_i  (wb.rst),
  .wb_adr_i  (wb.adr),
  .wb_dat_i  (wb.dat_m2s),
  .wb_dat_o  (wb.dat_s2m),
  .wb_we_i   (wb.we),
  .wb_stb_i  (wb.stb),
  .wb_cyc_i  (wb.cyc),
  .wb_ack_o  (wb.ack),
  .wb_sel_i  (wb.sel),
  .int_o     (wb.irq),
  .stx_pad_o (ser.stx),
  .srx_pad_i (ser.srx),
  .rts_pad_o (mdm.rts),
  .cts_pad_i (mdm.cts),
  .dtr_pad_o (mdm.dtr),
  .dsr_pad_i (mdm.dsr),
  .ri_pad_i  (mdm.ri),
  .dcd_pad_i (mdm.dcd)
`ifdef UART_HAS_BAUDRATE_OUTPUT
 ,.baud_o    (ser.baud)
`endif
);
```

El nombre de instancia (`dut`) importa: la cobertura de código (`+tree tb_top.dut`) y las rutas de puerta trasera del RAL dependen de él.

### 4.4 Aserciones con `bind`

El módulo de aserciones se escribe aparte y se "pega" al DUT sin tocar el RTL:

```systemverilog
bind uart_top uart_wb_sva u_wb_sva (
  .wb_clk_i (wb_clk_i),
  .wb_rst_i (wb_rst_i),
  ...
);
```

Dentro del `bind`, los nombres de la derecha son señales **de `uart_top`**, no del *top*. El ejemplo `uart_wb_sva.sv` trae dos propiedades para mostrar el formato (`assert` con mensaje y su `cover`). El conjunto completo de aserciones es parte del proyecto.

### 4.5 Entregar las interfaces al ambiente

Antes de `run_test()`, el *top* publica cada interfaz virtual en `uvm_config_db`:

```systemverilog
initial begin
  uvm_config_db#(virtual wb_if)::set      (null, "uvm_test_top*", "wb_vif",  wb);
  uvm_config_db#(virtual uart_ser_if)::set(null, "uvm_test_top*", "ser_vif", ser);
  uvm_config_db#(virtual modem_if)::set   (null, "uvm_test_top*", "mdm_vif", mdm);
  run_test();
end
```

Del lado del ambiente, la forma recomendada es que **la prueba obtenga las interfaces y las guarde en los objetos de configuración de cada agente**. Así el agente no busca la interfaz por su cuenta y se mantiene la regla de la sección 4.2 del enunciado (todo pasa por objetos de configuración):

```systemverilog
// En uart_base_test::build_phase
if (!uvm_config_db#(virtual wb_if)::get(this, "", "wb_vif", wb_cfg.vif))
  `uvm_fatal("NOVIF", "wb_vif no está en uvm_config_db")
uvm_config_db#(wb_agent_cfg)::set(this, "env.wb_agt*", "cfg", wb_cfg);

// En wb_agent::build_phase
if (!uvm_config_db#(wb_agent_cfg)::get(this, "", "cfg", cfg))
  `uvm_fatal("NOCFG", "wb_agent sin objeto de configuración")

// En wb_driver::run_phase (cfg obtenido igual que en el agente)
@(cfg.vif.drv_cb);
cfg.vif.drv_cb.stb <= 1'b1;
```

Si `get` falla, usen siempre `` `uvm_fatal ``: un ambiente sin interfaz no debe seguir corriendo.

## 5. Direccionamiento Wishbone en modo de 32 bits

Este es el error más común al instanciar el núcleo. En modo de 32 bits, el DUT **no usa los dos bits bajos de `wb_adr_i`**: los reconstruye a partir de `wb_sel_i` (ver `rtl/uart_wb.v`). Como el RTL no define `LITLE_ENDIAN`, el mapeo es *big endian*:

| Registro (índice de la especificación) | `wb_adr_i[4:2]` | `wb_sel_i` | Carril de datos |
|---|---|---|---|
| 0 (RBR / THR / DLL) | 0 | `4'b1000` | `[31:24]` |
| 1 (IER / DLM) | 0 | `4'b0100` | `[23:16]` |
| 2 (IIR / FCR) | 0 | `4'b0010` | `[15:8]` |
| 3 (LCR) | 0 | `4'b0001` | `[7:0]` |
| 4 (MCR) | 1 | `4'b1000` | `[31:24]` |
| 5 (LSR) | 1 | `4'b0100` | `[23:16]` |
| 6 (MSR) | 1 | `4'b0010` | `[15:8]` |
| 7 | 1 | `4'b0001` | `[7:0]` |
| Debug 1 (32 bits) | 2 | `4'b1111` | `[31:0]` |
| Debug 2 (32 bits) | 3 | `4'b1111` | `[31:0]` |

En forma compacta, para un registro de 8 bits con índice `r`:

```systemverilog
adr  = r;                         // el DUT solo mira adr[4:2]
sel  = 4'b1000 >> r[1:0];
dato = bus[8*(3 - r[1:0]) +: 8];
```

En la variante de 8 bits, `wb_adr_i` es directamente el índice del registro, `wb_sel_i` se ignora y el dato va en `[7:0]`.

Esto afecta al driver Wishbone y, sobre todo, al **adaptador del RAL** (`reg2bus` / `bus2reg`) y al mapa de direcciones (`uvm_reg_map`): definan el mapa con dirección por byte y ancho de bus de 4 bytes, y verifiquen que el adaptador genera el `sel` y el carril correctos.

Otra particularidad del DUT: registra las entradas Wishbone antes de usarlas, así que `wb_ack_o` llega dos ciclos después de que el maestro activa `stb`, y queda en 0 durante un par de ciclos después de cada transferencia. Su driver debe esperar `ack` y no suponer una latencia fija.

## 6. Rutas para la puerta trasera del RAL

Los registros internos están en la instancia `regs` de `uart_top`. Con el nombre de instancia del ejemplo, la raíz es `tb_top.dut`:

```systemverilog
// En el reg_block
add_hdl_path("tb_top.dut");

// En cada registro (ejemplo para LCR)
lcr.add_hdl_path_slice("regs.lcr", 0, 8);
```

Señales disponibles en `uart_regs.v`:

| Señal | Ancho | Contenido |
|---|---|---|
| `regs.ier` | 4 | IER bits 3:0 |
| `regs.iir` | 4 | IIR bits 3:0 |
| `regs.fcr` | 2 | FCR bits 7:6 (nivel de disparo) |
| `regs.lcr` | 8 | LCR completo |
| `regs.mcr` | 5 | MCR bits 4:0 |
| `regs.msr` | 8 | MSR completo |
| `regs.lsr` | 8 | LSR (`wire`: solo lectura por puerta trasera) |
| `regs.dl` | 16 | Divisor completo (DLM y DLL) |

Los registros no tienen todos sus bits implementados (por ejemplo, IER y MCR). Modelen en el RAL qué devuelve una lectura por puerta delantera de los bits no implementados y qué parte del registro cubre cada ruta. La lectura por puerta trasera de LSR, MSR e IIR no tiene los efectos laterales de la puerta delantera, por eso es útil para comprobar estado sin alterarlo.

## 7. La prueba de humo (`uart_hello_test`)

`uart_hello_pkg.sv` contiene una prueba que:

1. obtiene las tres interfaces de `uvm_config_db` (falla con `` `uvm_fatal `` si falta alguna),
2. espera el fin del reset,
3. lee LCR, IIR y LSR por Wishbone con el mapeo de la sección 5,
4. comprueba que LCR vale `0x03` después de reset y que `stx` está en reposo.

Sirve para confirmar que la instancia, las interfaces y la compilación están bien antes de empezar el ambiente. **No es una base para el proyecto**: accede a la interfaz directamente desde la prueba, cosa que en el ambiente final hace el driver del agente. Cuando tengan su `uart_base_test`, agreguen su paquete en `filelist.f` antes de `tb_top.sv`, impórtenlo en `tb_top.sv` y corran `make run TEST=uart_base_test`.

## 8. Errores comunes

| Síntoma | Causa probable |
|---|---|
| `Cannot open include file 'uart_defines.v'` | Falta `+incdir+../rtl` |
| `NOVIF` al iniciar | La ruta o el nombre en `set` no coincide con el `get`, o el `set` ocurre después de `run_test()` |
| `wb_ack_o` nunca llega | `cyc` o `stb` en X, el reset sigue activo, o el driver baja `stb` antes de `ack` |
| Se lee el registro equivocado | `wb_sel_i` incorrecto en modo de 32 bits (sección 5) |
| El receptor recibe basura desde el inicio | `srx` sin valor inicial o en 0 |
| No sale nada por `stx` | El divisor quedó en 0 (valor de reset) o se olvidó volver DLAB a 0 |
| Se leen DLL y DLM en lugar de RBR e IER | DLAB (LCR bit 7) quedó en 1 |
| La cobertura de código incluye el banco de pruebas | Falta `-cm_hier` con `+tree tb_top.dut` |
| Advertencias de `timescale` | Algún archivo del banco de pruebas sin `` `timescale ``; el Makefile usa `-timescale=1ns/1ps` como respaldo |

## 9. Origen y licencia del RTL

El RTL y la especificación vienen del proyecto [uart16550 de OpenCores](https://opencores.org/projects/uart16550), espejo [freecores/uart16550](https://github.com/freecores/uart16550), commit `2b0ad80` (22 de noviembre de 2004). El código está bajo la licencia GNU LGPL, indicada en el encabezado de cada archivo; no la eliminen.
