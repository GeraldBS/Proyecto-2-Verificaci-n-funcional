#!/bin/bash
# uso desde sim/ (despues del source de Synopsys):
#   ./regresion.sh humo              prueba de humo con 3 semillas
#   ./regresion.sh base 300          linea base, semillas 1 a 300 (30 para validar)
#   ./regresion.sh esquinas          los casos de tests/semillas.txt
#   ./regresion.sh todo 300          base y esquinas
# opciones antes del modo: -j 4 en paralelo, -s 1 semilla inicial, -n no recompilar

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
NBASE=${2:-30}

COV="line+cond+fsm+branch+tgl"
mkdir -p logs

# compilamos una sola vez; todas las corridas usan el mismo simv
if [ $COMPILE -eq 1 ]; then
  make comp || { echo "falló la compilación, revisen comp.log"; exit 1; }
fi

# una corrida: nombre semilla prueba, si existe tests/<nombre>.args se agrega
correr() {
  local nombre=$1 semilla=$2 prueba=$3
  local extra=""
  [ -f tests/$nombre.args ] && extra="-f tests/$nombre.args"
  ./simv +UVM_TESTNAME=$prueba +ntb_random_seed=$semilla \
         -cm $COV -cm_name ${nombre}_${semilla} +UVM_VERBOSITY=UVM_LOW \
         $extra -l logs/${nombre}_${semilla}.log > /dev/null 2>&1
}
export -f correr
export COV

lista=$(mktemp)
if [ "$MODE" = "humo" ]; then
  for s in 1 2 3; do echo "humo $s uart_smoke_test" >> $lista; done
fi
if [ "$MODE" = "base" ] || [ "$MODE" = "todo" ]; then
  for ((s = SEED0; s < SEED0 + NBASE; s++)); do echo "base $s uart_base_test" >> $lista; done
fi
if [ "$MODE" = "esquinas" ] || [ "$MODE" = "todo" ]; then
  grep -v '^#' tests/semillas.txt | while read caso n prueba; do
    [ -z "$caso" ] && continue
    for ((s = 1; s <= n; s++)); do echo "$caso $s $prueba" >> $lista; done
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

# curva de la linea base, una fila por semilla: semilla,episodio,cobertura
grep -H 'COV_CURVE' logs/base_*.log 2>/dev/null \
  | sed -E 's#logs/base_([0-9]+)\.log.*ep=([0-9]+) fcov=([0-9.]+).*#\1,\2,\3#' > curva_base.csv
echo "reporte HTML en cov_report/dashboard.html"
