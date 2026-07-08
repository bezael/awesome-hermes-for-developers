#!/usr/bin/env bash
# dump-mcp-subprocess-env.sh
#
# Servidor MCP "falso", de un solo uso, para el paso de verificación de
# references/credential-filtering.md: confirma qué variables de entorno realmente
# recibe un subproceso que Hermes lanza desde `mcp_servers`.
#
# NO es un servidor MCP real — no implementa el protocolo, así que Hermes va a
# fallar el handshake después de lanzarlo. Eso es esperado: el subproceso ya
# alcanzó a correr y volcar su entorno antes de que el handshake falle, que es
# todo lo que necesitas para esta prueba.
#
# Uso:
#   1. chmod +x dump-mcp-subprocess-env.sh
#   2. En ~/.hermes/config.yaml, sustituye TEMPORALMENTE el command/args de la
#      entrada que quieres auditar por:
#        command: /ruta/absoluta/a/dump-mcp-subprocess-env.sh
#        args: []
#        env:
#          <LAS MISMAS VARS QUE YA TENÍAS DECLARADAS PARA ESE SERVIDOR>
#   3. export CANARY_SHOULD_NOT_LEAK="si-ves-esto-el-filtrado-no-funciona"  (en tu shell,
#      ANTES de arrancar hermes — así puedes confirmar que NO se cuela al subproceso)
#   4. hermes doctor && hermes   (deja que intente conectar el "servidor", va a fallar
#      el handshake, eso es normal)
#   5. Revisa el archivo de salida (ruta impresa abajo) y confirma:
#        - Las variables que SÍ declaraste en el env: de ese servidor, presentes.
#        - PATH, HOME, USER, LANG, presentes (la base mínima documentada).
#        - CANARY_SHOULD_NOT_LEAK, AUSENTE.
#        - Cualquier otro secreto de tu shell (tokens de otros proyectos), AUSENTE.
#   6. Restaura la entrada real de config.yaml y borra la variable canario.

set -euo pipefail

OUT_FILE="${TMPDIR:-/tmp}/hermes-mcp-env-dump-$$.txt"

{
  echo "# Volcado de entorno del subproceso MCP — $(date -u +%FT%TZ)"
  echo "# PID: $$"
  echo "---"
  env | sort
} > "$OUT_FILE"

echo "Entorno volcado en: $OUT_FILE" >&2
echo "Revisa ese archivo para confirmar el filtrado de credenciales." >&2

# Salida no-cero intencional: esto no es un servidor MCP real, así que Hermes
# debe tratar el handshake como fallido en vez de quedarse esperando indefinidamente.
exit 1
