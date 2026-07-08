#!/usr/bin/env bash
# new-task.sh — crea un archivo de tarea en .hermes-cursor-handoff/pending/
#
# Uso:
#   ./new-task.sh --from hermes --to cursor --slug refactor-auth-middleware \
#     --title "Refactoriza el middleware de auth" [--dir .hermes-cursor-handoff]
#
# Imprime la ruta del archivo creado en stdout al terminar (para poder
# encadenarlo, ej. `path=$(./new-task.sh ...)`).

set -euo pipefail

dir=".hermes-cursor-handoff"
from=""
to=""
slug=""
title=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) from="$2"; shift 2 ;;
    --to) to="$2"; shift 2 ;;
    --slug) slug="$2"; shift 2 ;;
    --title) title="$2"; shift 2 ;;
    --dir) dir="$2"; shift 2 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$from" || -z "$to" || -z "$slug" ]]; then
  echo "Uso: $0 --from <hermes|cursor> --to <hermes|cursor> --slug <slug-corto> [--title \"...\"] [--dir <dir>]" >&2
  exit 1
fi

if [[ "$from" != "hermes" && "$from" != "cursor" ]]; then
  echo "--from debe ser 'hermes' o 'cursor', recibido: $from" >&2
  exit 1
fi
if [[ "$to" != "hermes" && "$to" != "cursor" ]]; then
  echo "--to debe ser 'hermes' o 'cursor', recibido: $to" >&2
  exit 1
fi

timestamp=$(date -u +%Y-%m-%dT%H-%M-%S)
id="${timestamp}-${slug}"
pending_dir="${dir}/pending"
mkdir -p "$pending_dir"
task_file="${pending_dir}/${id}.task.md"

if [[ -e "$task_file" ]]; then
  echo "Ya existe un task con ese id: $task_file" >&2
  exit 1
fi

created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

{
  echo "---"
  echo "id: ${id}"
  echo "from: ${from}"
  echo "to: ${to}"
  echo "status: pending"
  echo "created_at: ${created_at}"
  echo "repo_path: ."
  echo "branch: main"
  echo "---"
  echo ""
  echo "## Tarea"
  echo ""
  if [[ -n "$title" ]]; then
    echo "${title}"
  else
    echo "<describe la tarea aquí>"
  fi
  echo ""
  echo "## Contexto"
  echo ""
  echo "- Archivo(s) relevante(s):"
  echo "- Tests relevantes (si aplica):"
  echo ""
  echo "## Criterio de aceptación"
  echo ""
  echo "- <cómo sabe el receptor que terminó>"
} > "$task_file"

echo "$task_file"
