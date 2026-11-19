# Medición en crudo de la Iteración 5

Los 117 volcados de contadores (39 programas × 3 niveles) de los que salen las
tablas de `documentacion/ITERACION5_NIVELES.md`. Se incluyen para que las
cifras del informe sean verificables sin volver a correr la simulación, que
toma del orden de media hora.

Cada archivo se llama `<ruta_del_fuente_aplanada>.O<nivel>.txt` y lleva un
`clave valor` por línea. Los contadores son los de
`ARQUITECTURA/src/cpu/perf_counters.sv`, leídos del DUT al final de la
ejecución; `desbordado` es pegajoso y vale 1 si algún contador llegó al tope,
en cuyo caso toda cifra derivada de él es falsa.

Rehacer las tablas sin simular:

```bash
make tabla-niveles METRICAS_DIR=medicion
```

Volver a medir desde cero:

```bash
make medir-niveles METRICAS_DIR=medicion_nueva
```

La medición se recoge dentro de `test/run_equivalencia.sh`, así que la corrida
que produce estos archivos es la misma que comprueba que los tres niveles dan
el mismo resultado. Esa corrida reportó `equivalencia RTL: 117 correctas, 0
fallidas (-O0/-O1/-O2)`.
