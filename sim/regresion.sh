#!/bin/bash
######################################################################
# regresion.sh: corre la prueba base con muchas semillas y los casos
# de esquina, y fusiona la cobertura con urg
######################################################################
# Uso (desde sim/, después de hacer el source de Synopsys):
#   ./regresion.sh base 350          línea base: semillas 1 a 350
#   ./regresion.sh esquinas          cada .args de tests/semillas.txt
#   ./regresion.sh todo 350          las dos cosas
# Opciones (antes del modo):
#   -j 4       corridas en paralelo (por defecto 4)
#   -s 1       semilla inicial de la línea base (por defecto 1)
#   -n         no recompilar
# Al final deja logs/, cov_report/ y resumen.txt.
######################################################################

JOBS=4
SEED0=1
COMPILE=1
while getopts "j:s:n" opt; do
  case $opt in
    j) JOBS=$OPTARG ;;
    s) SEED0=$OPTARG ;;
    n) COMPILE=0 ;;
    *) echo "opción desconocida"; exit 1 ;;
  esac
done
shift $((OPTIND - 1))
MODE=${1:-base}
NBASE=${2:-20}

COV="line+cond+fsm+branch+tgl"
mkdir -p logs

# compilamos una sola vez; todas las corridas usan el mismo simv
if [ $COMPILE -eq 1 ]; then
  make comp || { echo "falló la compilación, revisen comp.log"; exit 1; }
fi

# una corrida: nombre semilla [archivo .args]
correr() {
  local nombre=$1 semilla=$2 args=$3
  local extra=""
  [ -n "$args" ] && extra="-f tests/$args.args"
  ./simv +UVM_TESTNAME=uart_base_test +ntb_random_seed=$semilla \
         -cm $COV -cm_name ${nombre}_${semilla} +UVM_VERBOSITY=UVM_LOW \
         $extra -l logs/${nombre}_${semilla}.log > /dev/null 2>&1
}
export -f correr
export COV

lista=$(mktemp)
if [ "$MODE" = "base" ] || [ "$MODE" = "todo" ]; then
  for ((s = SEED0; s < SEED0 + NBASE; s++)); do echo "base $s" >> $lista; done
fi
if [ "$MODE" = "esquinas" ] || [ "$MODE" = "todo" ]; then
  grep -v '^#' tests/semillas.txt | while read caso n; do
    [ -z "$caso" ] && continue
    for ((s = 1; s <= n; s++)); do echo "$caso $s $caso" >> $lista; done
  done
fi

echo "corriendo $(wc -l < $lista) simulaciones con $JOBS en paralelo..."
xargs -P $JOBS -L 1 bash -c 'correr $0 $1 $2' < $lista
rm -f $lista

# fusionar la cobertura de todas las corridas
urg -full64 -dir simv.vdb -dbname merged -report cov_report -format both > logs/urg.log 2>&1

# resumen: cuántas pasaron y cuáles fallaron
{
  echo "Resumen de la regresión ($(date))"
  echo "pasaron: $(grep -l 'RESULT.*PASA' logs/*_*.log | wc -l)"
  echo "fallaron:"
  for f in logs/*_*.log; do
    grep -q 'RESULT.*PASA' $f || echo "  $f"
  done
  echo "diferencias conocidas del DUT (DUT_BUG): $(grep -h 'DUT_BUG' logs/*_*.log | wc -l)"
  grep -h 'cobertura funcional total' logs/base_*.log | tail -1
} | tee resumen.txt

# curva por episodio de cada semilla de la línea base: semilla,episodio,cobertura
grep -H 'COV_CURVE' logs/base_*.log 2>/dev/null \
  | sed -E 's#logs/base_([0-9]+)\.log.*ep=([0-9]+) fcov=([0-9.]+).*#\1,\2,\3#' > curva_base.csv
echo "reporte HTML en cov_report/dashboard.html"
