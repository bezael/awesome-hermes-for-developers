# MCP

Skills para **crear, validar y conectar servidores MCP (Model Context Protocol)** a Hermes Agent —
no para explicar qué es MCP. Hermes ya habla MCP nativamente (`mcp_servers:` en
`~/.hermes/config.yaml`); lo que falta es ayuda del lado de autoría/wireup de esos servidores.

## Skills recomendadas

### [`backnotprop/build-mcp-server`](https://github.com/backnotprop/build-mcp-server)
Skill portable para **diseñar y construir** servidores MCP: guía por fases de descubrimiento del
caso de uso, elección de transporte (remoto Streamable HTTP vs. stdio local), diseño de
tools/resources/prompts, auth del propio servidor, scaffold, pruebas con MCP Inspector y checklist
de deployment. Es el complemento natural de la skill original de este repo (abajo): esta construye
el servidor, la nuestra lo conecta a Hermes.

### [`aptratcn/skill-mcp-builder`](https://github.com/aptratcn/skill-mcp-builder)
Guía más compacta para construir servidores MCP "production-ready" — patrones de tools, resources
y prompts, con integraciones de ejemplo. Menor tracción y alcance más modesto que
`build-mcp-server`, pero cubre el mismo problema (autoría de servidor) desde otro ángulo.

### [`sno-ai/mda`](https://github.com/sno-ai/mda) — mención honesta, no recomendación directa
Superset de Markdown que compila una sola fuente `.mda` hacia `SKILL.md`, `AGENTS.md`,
`MCP-SERVER.md` y `CLAUDE.md`. Es meta-tooling de documentación (mantener un solo source of truth
para varios formatos de agente) — genera el *documento* `MCP-SERVER.md`, no te ayuda a diseñar,
construir o conectar el servidor en sí. Tangencial a este caso de uso, no una skill de MCP puntual;
lo incluimos porque es el candidato de mayor tracción que encontramos buscando en esta dirección y
sería deshonesto omitirlo solo porque no encaja limpio en la categoría.

## Nivel de madurez

| Skill | Stars | Última actualización | Licencia |
|---|---|---|---|
| build-mcp-server | 3 | 2026-06-29 | **Sin licencia declarada en el repo** |
| skill-mcp-builder | 2 | 2026-04-23 | MIT (declarada en el archivo `LICENSE`; GitHub no le asigna SPDX automáticamente) |
| mda | 610 | 2026-05-26 | Apache-2.0 |

*Los dos candidatos directamente relevantes (`build-mcp-server`, `skill-mcp-builder`) tienen
tracción mínima (2-3 stars) — trátalos con la misma cautela que cualquier dependencia que acabas de
descubrir, no como algo validado por uso masivo. `build-mcp-server` no declara licencia: confirma
los términos con el autor antes de usar su código más allá de experimentación personal.*

## Casos de uso

- Diseñar un servidor MCP nuevo desde el caso de uso (qué expone, quién se conecta, tools vs.
  resources vs. prompts) en vez de improvisar la forma del servidor sobre la marcha.
- Migrar una entrada de `mcp.json` (Claude Desktop, Cursor, Claude Code) hacia el
  `mcp_servers:` de `~/.hermes/config.yaml` de Hermes sin asumir campos que no existen del otro
  lado.
- Diagnosticar por qué las tools de un servidor MCP no aparecen en Hermes, o por qué una tool call
  falla con lo que parece un error de auth pero en realidad es una env var que nunca llegó al
  subproceso.
- Auditar si el filtrado de credenciales de subprocesos MCP que documenta Hermes de verdad está
  pasando en tu instalación, en vez de solo confiar en el texto del doc.

## Instalación

```bash
hermes skills install https://raw.githubusercontent.com/<owner>/<repo>/main/<ruta-a-la-skill>/SKILL.md --force
```

`build-mcp-server` trae un único `SKILL.md` en `skills/build-mcp-server/SKILL.md` — revisa su
propio README para el comando `npx skills add` que usa como instalador alternativo. Para la skill
original de este repo, la ruta es `MCP/skills/mcp-server-wireup/SKILL.md` (ver abajo).

## Skill original — creada por Dominicode

### [`mcp-server-wireup`](./skills/mcp-server-wireup/SKILL.md)

Ninguno de los candidatos encontrados cubre el lado de **Hermes** del problema: una vez que el
servidor MCP ya existe (oficial, de la comunidad, o construido con una de las skills de arriba),
¿cómo lo conectas de forma segura a una instancia real de Hermes? Esta skill llena ese hueco:

- Agregar la entrada correcta bajo `mcp_servers:` en `~/.hermes/config.yaml` (clave de nivel raíz,
  no anidada — el error de indentación más común).
- Declarar variables de entorno explícitamente, entendiendo que los subprocesos MCP de Hermes
  **no** heredan tu shell completo — solo `PATH`, `HOME`, `USER`, `LANG` más lo que declares.
- Una tensión real de la propia documentación de Hermes, señalada sin resolver artificialmente: el
  checklist general dice "secretos en `.env`, nunca en `config.yaml`", pero el único mecanismo
  documentado para credenciales de MCP es escribirlas justo en `config.yaml`.
- Verificar con una prueba canario de entorno (`scripts/dump-mcp-subprocess-env.sh` en la propia
  skill) que el filtrado de credenciales documentado de verdad está pasando, en vez de solo
  confiar en el texto del doc.

**Estado: ilustrativa, no ejecutada aún contra una instancia real de Hermes.** Está escrita a
partir del mecanismo `mcp_servers` documentado en la chuleta de Hermes Agent de Dominicode y en
`hermes-agent.nousresearch.com/docs` — no como algo que ya corrimos de punta a punta. Los pasos de
verificación de la skill están diseñados justamente para que quien la instale confirme el
comportamiento en su propia instancia antes de confiar en ella para producción.

Instalación (una vez publicada en un repo propio o instalada localmente):

```bash
hermes skills install https://raw.githubusercontent.com/<tu-fork>/awesome-hermes-for-developers/main/MCP/skills/mcp-server-wireup/SKILL.md --force
```

## Vídeo demostración

*Pendiente de grabar.* Guion propuesto (3-4 min):
1. Tomar un servidor MCP real (ej. `@modelcontextprotocol/server-github`) y conectarlo a una
   instancia limpia de Hermes usando `mcp-server-wireup`.
2. Mostrar el error típico de env var faltante (tool call fallando como si fuera auth del
   servicio externo) y cómo el flujo de la skill lo diagnostica.
3. Correr la prueba canario de `dump-mcp-subprocess-env.sh` en vivo para mostrar el filtrado de
   credenciales funcionando (o no) contra la instancia real.

## Ejemplo real

*Pendiente* — no hemos corrido `mcp-server-wireup` ni los dos candidatos de autoría de servidor
contra un proyecto real todavía. Se actualiza con output real (incluyendo el resultado de la
prueba canario) una vez grabado el vídeo — no antes.
