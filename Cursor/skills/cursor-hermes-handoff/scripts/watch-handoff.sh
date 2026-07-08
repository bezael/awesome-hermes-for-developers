#!/usr/bin/env bash
# watch-handoff.sh — sondea .hermes-cursor-handoff/pending/ y notifica (stdout)
# cada tarea nueva dirigida a --to que todavía no se haya reportado.
#
# Uso:
#   ./watch-handoff.sh --to cursor --dir .hermes-cursor-handoff [--interval 5] [--once]
#
# --once corre un solo pase y termina (útil para pruebas / cron externo).
# Sin --once, corre en loop hasta Ctrl+C.
#
# No mueve archivos ni cambia su status — solo notifica. Mover a
# in_progress/tomar la tarea es responsabilidad de quien la procesa
# (ver complete-task.sh para el otro extremo del flujo).

set -euo pipefail

dir=".hermes-cursor-handoff"
to=""
interval=5
once=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --to) to="$2"; shift 2 ;;
    --dir) dir="$2"; shift 2 ;;
    --interval) interval="$2"; shift 2 ;;
    --once) once=true; shift ;;
    *) echo "Argumento desconocido: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$to" ]]; then
  echo "Uso: $0 --to <hermes|cursor> [--dir <dir>] [--interval <segundos>] [--once]" >&2
  exit 1
fi

pending_dir="${dir}/pending"
mkdir -p "$pending_dir"
seen_file="${dir}/.watch-seen-${to}"
touch "$seen_file"

check_once() {
  local found_new=false
  shopt -s nullglob
  for f in "$pending_dir"/*.task.md; do
    local id
    id=$(basename "$f" .task.md)

    # ya notificado
    if grep -qxF "$id" "$seen_file" 2>/dev/null; then
      continue
    fi

    local file_to file_status
    file_to=$(sed -n 's/^to:[[:space:]]*//p' "$f" | head -n1 | tr -d '\r')
    file_status=$(sed -n 's/^status:[[:space:]]*//p' "$f" | head -n1 | tr -d '\r')

    if [[ "$file_to" == "$to" && "$file_status" == "pending" ]]; then
      echo "[nueva tarea] ${id} -> ${f}"
      echo "$id" >> "$seen_file"
      found_new=true
    fi
  done
  shopt -u nullglob
  $found_new
}

if $once; then
  check_once || true
  exit 0
fi

echo "Vigilando ${pending_dir} para tareas dirigidas a '${to}' (cada ${interval}s, Ctrl+C para salir)"
while true; do
  check_once || true
  sleep "$interval"
done
