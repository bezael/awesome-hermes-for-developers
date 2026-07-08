# `mcp_servers` en `~/.hermes/config.yaml` — qué está confirmado y qué no

Fuente primaria: la chuleta de comandos de Hermes Agent de Dominicode (verificada contra
`hermes-agent.nousresearch.com/docs` a la fecha de redacción) y el archivo de config de hardening
que la acompaña. Si tu versión de Hermes difiere, `hermes doctor` y el changelog oficial mandan
sobre este documento.

## Forma confirmada

```yaml
mcp_servers:
  <alias>:
    command: <string>        # binario o ejecutable a lanzar
    args: [<string>, ...]     # argumentos, como lista
    env:                       # opcional — variables explícitas para el subproceso
      <VAR_NAME>: "<valor>"
```

- `mcp_servers` es una clave de **nivel raíz** en `config.yaml`, hermana de `terminal:` y
  `approvals:` — no va anidada dentro de ninguna de las dos.
- `<alias>` es arbitrario (el ejemplo oficial usa `github`) — es el nombre bajo el que Hermes
  identifica ese servidor internamente.
- `command` + `args` siguen el mismo patrón que cualquier invocación de MCP por stdio (idéntico en
  espíritu a `mcp.json` de Claude Desktop/Cursor): un ejecutable y su lista de argumentos.
- `env` es un mapa plano `NOMBRE: "valor"`. No confirmado si acepta referencias a variables ya
  exportadas en el shell (sintaxis tipo `${VAR}`) — trátalo como strings literales hasta que
  confirmes lo contrario en tu versión instalada.

## Campos que existen en OTROS clientes MCP pero no están confirmados en Hermes

Si vienes de migrar un `mcp.json` de Claude Desktop o Cursor, es tentador copiar todo el objeto tal
cual. Ten cuidado con estos campos — existen en esos clientes, pero no aparecen en la documentación
de Hermes que hemos podido verificar:

| Campo | Dónde se usa | Estado en Hermes |
|---|---|---|
| `disabled` | Claude Desktop / Cursor | No confirmado — si quieres desactivar un servidor sin borrar la entrada, comenta el bloque YAML en vez de asumir que existe este flag |
| `alwaysAllow` | Claude Desktop | No confirmado — el modelo de aprobaciones de Hermes vive en el bloque `approvals:` separado (`mode: manual/smart/off`), no por servidor MCP |
| `cwd` por servidor | Varios clientes | No confirmado a nivel de servidor individual — Hermes sí tiene `terminal.cwd` global, pero eso limita el directorio de trabajo del *agente*, no necesariamente el del subproceso MCP |
| Transporte HTTP/SSE remoto declarado inline | Varios clientes MCP más recientes | No confirmado en los docs de Hermes revisados — la única forma documentada que hemos visto es `command`+`args` (stdio) |

Si necesitas alguno de estos, confírmalo primero contra tu versión instalada (`hermes --version`,
`hermes doctor`, changelog oficial) antes de depender de él en un setup de producción.

## Comparación rápida con `mcp.json` (Claude Desktop / Cursor / Claude Code)

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_xxx" }
    }
  }
}
```

La migración a Hermes es casi mecánica para el caso stdio simple: `mcpServers` (camelCase, JSON) se
convierte en `mcp_servers` (snake_case, YAML), y cada entrada mantiene `command`/`args`/`env`. Lo
que **no** se traduce automáticamente son los campos de la tabla de arriba — si tu `mcp.json`
depende de `disabled` o `alwaysAllow`, resuelve ese comportamiento del lado de Hermes con
`approvals:` en vez de buscar un campo equivalente que quizás no exista.
