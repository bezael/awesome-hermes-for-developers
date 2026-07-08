#!/usr/bin/env bash
# verify-mcp-wireup.sh
#
# Chequeos previos-al-"ya quedó" para una entrada nueva bajo mcp_servers en
# ~/.hermes/config.yaml. No reemplaza los pasos manuales de Verification en
# SKILL.md (listar tools, hacer una tool call real, prueba canario de entorno)
# — solo automatiza lo que sí se puede automatizar sin una sesión interactiva
# de Hermes: sintaxis, indentación de la clave, y permisos del archivo.
#
# Uso: ./verify-mcp-wireup.sh [ruta-a-config.yaml]
# Por defecto usa ~/.hermes/config.yaml

set -uo pipefail

CONFIG_PATH="${1:-$HOME/.hermes/config.yaml}"
FAIL=0

echo "== Verificando: $CONFIG_PATH =="

if [ ! -f "$CONFIG_PATH" ]; then
  echo "[FAIL] No existe: $CONFIG_PATH"
  exit 1
fi

# 1. Sintaxis YAML válida (usa python3 si está disponible; si no, avisa y sigue)
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import sys, yaml" >/dev/null 2>&1; then
    if python3 -c "import yaml, sys; yaml.safe_load(open(sys.argv[1]))" "$CONFIG_PATH" 2>/tmp/yaml-err.$$; then
      echo "[OK] YAML parsea sin errores"
    else
      echo "[FAIL] YAML inválido:"
      cat /tmp/yaml-err.$$
      FAIL=1
    fi
    rm -f /tmp/yaml-err.$$
  else
    echo "[SKIP] python3 no tiene PyYAML instalado — instala con 'pip install pyyaml' para este chequeo, o confía en 'hermes doctor'"
  fi
else
  echo "[SKIP] python3 no disponible — confía en 'hermes doctor' para validar sintaxis"
fi

# 2. mcp_servers debe existir como clave de nivel raíz (columna 0, sin indentación)
if grep -qE '^mcp_servers:' "$CONFIG_PATH"; then
  echo "[OK] 'mcp_servers:' encontrado como clave de nivel raíz"
elif grep -qE '^\s+mcp_servers:' "$CONFIG_PATH"; then
  echo "[FAIL] 'mcp_servers:' está indentado — debe ser una clave de nivel raíz, hermana de 'terminal:' y 'approvals:', no anidada dentro de ninguna"
  FAIL=1
elif grep -qE '^#\s*mcp_servers:' "$CONFIG_PATH"; then
  echo "[WARN] 'mcp_servers:' está comentado — probablemente sigues en la plantilla de ejemplo, no lo has activado todavía"
else
  echo "[WARN] No se encontró 'mcp_servers:' en el archivo — ¿ya agregaste el bloque?"
fi

# 3. Si hay algo que huela a secreto bajo mcp_servers, exige permisos restrictivos
if grep -qE '^\s*mcp_servers:' "$CONFIG_PATH" && grep -qE '(TOKEN|KEY|SECRET|PASSWORD)' "$CONFIG_PATH"; then
  PERMS="$(stat -c '%a' "$CONFIG_PATH" 2>/dev/null || stat -f '%Lp' "$CONFIG_PATH" 2>/dev/null || echo '???')"
  if [ "$PERMS" = "600" ] || [ "$PERMS" = "400" ]; then
    echo "[OK] Permisos de $CONFIG_PATH ($PERMS) restringen lectura a otros usuarios"
  else
    echo "[FAIL] $CONFIG_PATH parece contener un secreto (TOKEN/KEY/SECRET/PASSWORD) pero sus permisos son $PERMS — corre: chmod 600 $CONFIG_PATH"
    FAIL=1
  fi
fi

# 4. Recuerda el paso que este script NO puede automatizar
echo
echo "Este script no reemplaza:"
echo "  - 'hermes doctor' (corre esto también)"
echo "  - Confirmar que las tools del servidor cargan en una sesión real de Hermes"
echo "  - Una tool call real contra el servidor"
echo "  - La prueba canario de entorno (ver dump-mcp-subprocess-env.sh)"

if [ "$FAIL" -ne 0 ]; then
  echo
  echo "== Resultado: FAIL — revisa los puntos marcados arriba =="
  exit 1
fi

echo
echo "== Resultado: OK (chequeos automatizables) =="
