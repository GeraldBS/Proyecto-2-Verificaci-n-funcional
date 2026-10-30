# UART 16550: archivos fuente del proyecto UVM

Paquete base para el proyecto de verificación funcional del UART 16550 con Synopsys VCS y UVM 1.2.

| Carpeta | Contenido |
|---|---|
| `rtl/` | RTL completo del DUT (`uart_top` y submódulos). No se modifica. |
| `doc/` | `UART_spec.pdf`, especificación del núcleo y documento normativo del proyecto; `CHANGES.txt`, historial del autor. |
| `tb/` | Ejemplo mínimo de instancia: interfaces, módulo superior, `bind` de aserciones y una prueba de humo. |
| `sim/` | `filelist.f` y `Makefile` para VCS. |
| `TUTORIAL.md` | Cómo instanciar el DUT dentro de un ambiente UVM, paso a paso. |

Arranque rápido:

```sh
cd sim
make
```

Empiecen por `TUTORIAL.md`. La especificación del proyecto (enunciado) indica qué deben construir a partir de esta base.

Origen del RTL: [uart16550 de OpenCores](https://opencores.org/projects/uart16550), espejo [freecores/uart16550](https://github.com/freecores/uart16550), commit `2b0ad80`. Licencia GNU LGPL (ver el encabezado de cada archivo de `rtl/`).
