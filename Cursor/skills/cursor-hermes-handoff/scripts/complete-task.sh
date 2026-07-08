#!/usr/bin/env bash
# complete-task.sh — cierra una tarea: escribe el result.md y mueve el par
# task.md + result.md a done/ o failed/.
#
# Uso:
#   ./complete-task.sh --id <id> --status done \
#     --summary "Refactorizado a async/await" \
#     --files "src/a.ts,src/b.ts" \
#     [--diff-ref <sha-o-ruta-a-patch>] \
#     [--dir .hermes-cursor-handoff]

set -euo pipefail

dir=".hermes-cursor-handoff"
id=""
status=""
summary=""
files=""
diff_ref=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) id="$2"; shift 2 ;;
    --status) status="$2"; shift 2 ;;
    --summary) summary="$2"; shift 2 ;;
    --files) files="$2"; shift 2 ;;
    --diff-ref) diff_ref="$2"; shift 2 ;;
    --dir) dir="$2"; shift 2 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$id" || -z "$status" ]]; then
  echo "Uso: $0 --id <id> --status <done|failed> --summary \"...\" [--files \"a,b,c\"] [--diff-ref <ref>] [--dir <dir>]" >&2
  exit 1
fi

if [[ "$status" != "done" && "$status" != "failed" ]]; then
  echo "--status debe ser 'done' o 'failed', recibido: $status" >&2
  exit 1
fi

# Busca el task.md en pending/ o in_progress/ (lo que exista primero)
task_file=""
for candidate_dir in "${dir}/pending" "${dir}/in_progress"; do
  if [[ -f "${candidate_dir}/${id}.task.md" ]]; then
    task_file="${candidate_dir}/${id}.task.md"
    break
  fi
done

if [[ -z "$task_file" ]]; then
  echo "No se encontró ${id}.task.md en ${dir}/pending ni ${dir}/in_progress" >&2
  exit 1
fi

source_dir=$(dirname "$task_file")
result_file="${source_dir}/${id}.result.md"
completed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

{
  echo "---"
  echo "task_id: ${id}"
  echo "status: ${status}"
  echo "completed_at: ${completed_at}"
  if [[ -n "$files" ]]; then
    echo "files_changed:"
    IFS=',' read -ra file_arr <<< "$files"
    for f in "${file_arr[@]}"; do
      echo "  - ${f}"
    done
  fi
  if [[ -n "$diff_ref" ]]; then
    echo "diff_ref: ${diff_ref}"
  fi
  echo "---"
  echo ""
  echo "## Resumen"
  echo ""
  echo "${summary:-<sin resumen>}"
} > "$result_file"

# Actualiza el campo status: dentro del task.md original
tmp_task=$(mktemp)
sed "s/^status:.*/status: ${status}/" "$task_file" > "$tmp_task"
mv "$tmp_task" "$task_file"

target_dir="${dir}/${status}"
mkdir -p "$target_dir"
mv "$task_file" "$target_dir/"
mv "$result_file" "$target_dir/"

echo "${target_dir}/${id}.task.md"
echo "${target_dir}/${id}.result.md"
