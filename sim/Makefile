# -----------------------------------------------------------------------------
# Makefile mínimo para compilar y correr con Synopsys VCS + UVM 1.2
#
#   make                       compila y corre uart_hello_test con semilla 1
#   make run TEST=x SEED=42    corre otra prueba o semilla (sin recompilar)
#   make run ARGS="-f ../tests/caso.args"
#   make BUS8=1                compila la variante de bus de 8 bits
#   make cov                   fusiona la cobertura y genera el reporte HTML
#   make verdi                 abre Verdi con la base de datos de compilación
# -----------------------------------------------------------------------------

TEST  ?= uart_hello_test
SEED  ?= 1
ARGS  ?=
BUS8  ?= 0
FSDB  ?= 0

DEFINES :=
ifeq ($(BUS8),1)
  DEFINES += +define+DATA_BUS_WIDTH_8
endif
ifeq ($(FSDB),1)
  DEFINES += +define+DUMP_FSDB
endif

COV_TYPES := line+cond+fsm+branch+tgl

VCS_OPTS := -full64 -sverilog -ntb_opts uvm-1.2 \
            -timescale=1ns/1ps \
            -debug_access+all -kdb \
            -cm $(COV_TYPES) -cm_hier cov_hier.cfg \
            $(DEFINES) \
            -f filelist.f \
            -top tb_top \
            -l comp.log

SIMV_OPTS := +UVM_TESTNAME=$(TEST) +ntb_random_seed=$(SEED) \
             -cm $(COV_TYPES) -cm_name $(TEST)_$(SEED) \
             +UVM_VERBOSITY=UVM_LOW \
             $(ARGS) \
             -l run_$(TEST)_$(SEED).log

.PHONY: all comp run cov verdi clean

all: comp run

comp: cov_hier.cfg
	vcs $(VCS_OPTS)

run:
	./simv $(SIMV_OPTS)

# Solo el DUT cuenta para la cobertura de código.
cov_hier.cfg:
	echo "+tree tb_top.dut" > $@

cov:
	urg -full64 -dir simv.vdb -dbname merged -report cov_report -format both

verdi:
	verdi -dbdir simv.daidir -ssf waves.fsdb &

clean:
	rm -rf simv simv.daidir simv.vdb csrc ucli.key vc_hdrs.h \
	       *.log *.fsdb cov_report merged.vdb cov_hier.cfg \
	       novas* verdiLog AN.DB
