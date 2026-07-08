# Cursor

Skills y plugins que conectan Hermes Agent con [Cursor](https://cursor.com) — no herramientas genéricas que soportan Cursor entre 17-60+ agentes, sino puentes reales entre ambos para delegar trabajo de un lado a otro. Mismo criterio que aplicamos en la categoría Claude Code de este catálogo.

Una búsqueda inicial solo encontró colecciones multi-plataforma (`OthmanAdi/planning-with-files`, 25,016 ⭐; `FrancyJGLisboa/agent-skill-creator`, 1,766 ⭐) que mencionan Cursor de pasada, junto a decenas de otros agentes. Son legítimas y muy usadas, pero no son puentes Hermes↔Cursor específicos, así que no las contamos como "skills recomendadas" de esta categoría — búscalas si quieres skills genéricas que funcionen en cualquier agente.

Buscando específicamente (`cursor hermes bridge`, `hermes agent cursor acp`) sí aparecieron varios puentes reales y recientes. Documentamos los tres más sólidos, y además escribimos una skill propia (`cursor-hermes-handoff`) para el caso en que no quieras instalar ninguno de los tres todavía.

## Skills recomendadas

### [`Cosmic-Construct/hermes-cursor-harness`](https://github.com/Cosmic-Construct/hermes-cursor-harness)
El más completo de los tres: un plugin de Hermes que convierte a Cursor en un runtime de código embebido, con `@cursor/sdk` como transporte principal y fallback automático a ACP (`agent acp`) y a `stream-json` si el SDK no está disponible. Trae registro de sesiones, logs de eventos, modos de permiso (`plan`/`ask`/`edit`/`full_access`/`reject`) y un canal de retorno (proposal inbox) para revisar cambios antes de aceptarlos.

### [`tommulkins/cursor-hermes-bridge`](https://github.com/tommulkins/cursor-hermes-bridge)
Servidor MCP en Node.js puro (sin dependencias) que expone `cursor_agent_code` como tool de Hermes. Por dentro habla ACP con `cursor agent acp`, reutiliza el login existente de Cursor (sin API key nueva) y cachea sesiones por repo para preservar contexto entre prompts con `resume_session`.

### [`nirvana6/hermes-mcp-bridge`](https://github.com/nirvana6/hermes-mcp-bridge)
Va en la dirección contraria a los dos anteriores: deja que **Cursor** llame a **Hermes** como sub-agente. Bridge stdio (no HTTP) que evita el OAuth 2.1 + Dynamic Client Registration que rompe la integración MCP nativa de Cursor. Expone `hermes_ask` con continuidad de sesión (`session_id`) para que Hermes recuerde contexto entre turnos del mismo chat de Cursor.

## Nivel de madurez

| Skill | Stars | Última actualización | Licencia |
|---|---|---|---|
| hermes-cursor-harness | 5 | 2026-05-01 | MIT |
| cursor-hermes-bridge (tommulkins) | 0 | 2026-05-16 | Sin licencia declarada |
| hermes-mcp-bridge (nirvana6) | 1 | 2026-07-04 | Apache-2.0 |

*Stars de un solo dígito en los tres — es una categoría joven, con puentes publicados entre abril y julio de 2026. Ninguno tiene el volumen de uso de las skills de Claude Code (47-92 ⭐). Revisa el código antes de darle acceso a tu servidor, con más razón todavía cuando la skill casi no la ha probado nadie más.*

*`tommulkins/cursor-hermes-bridge` no declara licencia — antes de usarlo en algo que no sea experimentación personal, confirma los términos con el autor.*

## Casos de uso

- Que Hermes delegue un refactor o una tarea de código "seria" a Cursor (composer-2 / los modelos que ya tienes contratados en tu plan Cursor Pro) sin abrir la IDE
- Que Cursor use a Hermes como sub-agente para tareas que Hermes ya resuelve bien (investigación, memoria de largo plazo, skills instaladas) sin salir del chat de Cursor
- Revisar y aprobar cambios propuestos por Cursor antes de aceptarlos, en vez de darle `--yolo` / permisos totales de entrada
- Delegar una tarea puntual sin instalar ningún bridge todavía — usando el protocolo de archivos de `cursor-hermes-handoff` (ver abajo)

## Instalación

Los tres bridges reales requieren configuración explícita — no son un único `SKILL.md` instalable con un comando:

```bash
# hermes-cursor-harness: plugin de Hermes
git clone https://github.com/Cosmic-Construct/hermes-cursor-harness
cd hermes-cursor-harness && ./install.sh
# luego habilitar "hermes-cursor-harness" en ~/.hermes/config.yaml

# tommulkins/cursor-hermes-bridge: servidor MCP para Hermes (Node.js puro, sin build)
git clone https://github.com/tommulkins/cursor-hermes-bridge ~/.hermes/integrations/cursor-hermes-bridge
hermes mcp add cursor-agent --command node --args ~/.hermes/integrations/cursor-hermes-bridge/src/cursor-mcp-server.js

# nirvana6/hermes-mcp-bridge: bridge stdio para que Cursor llame a Hermes
git clone https://github.com/nirvana6/hermes-mcp-bridge && cd hermes-mcp-bridge
uv tool install --editable .
# luego registrar el binario en ~/.cursor/mcp.json bajo "mcpServers"
```

Todos asumen que ya tienes Cursor instalado y logueado (`cursor-agent status` o el propio login de la app) y, en el caso de `hermes-mcp-bridge`, un gateway de Hermes corriendo localmente.

### Skill original: `cursor-hermes-handoff`

Este catálogo incluye además una skill propia de Dominicode en
[`skills/cursor-hermes-handoff/`](./skills/cursor-hermes-handoff/SKILL.md) — un
protocolo de handoff por **archivos compartidos** (task/result en Markdown con
frontmatter) para delegar una tarea puntual entre Hermes y Cursor sin instalar
ninguno de los bridges de arriba. Es deliberadamente más simple: no hay
streaming ni sesión persistente, solo un archivo que uno escribe y el otro
recoge.

```bash
hermes skills install https://raw.githubusercontent.com/<owner>/awesome-hermes-for-developers/main/Cursor/skills/cursor-hermes-handoff/SKILL.md --force
```

**Es ilustrativa** — los tres scripts (`new-task.sh`, `watch-handoff.sh`,
`complete-task.sh`) se probaron localmente contra el filesystem (crean,
notifican y mueven archivos como se espera), pero la skill **no se ha
ejecutado aún contra un Hermes real** ni contra una sesión real de Cursor.
Detalle completo en la sección "Verification" de su `SKILL.md`.

## Vídeo demostración

*Pendiente de grabar.* Guion propuesto (3-4 min):
1. Registrar `tommulkins/cursor-hermes-bridge` como MCP server en una instancia real de Hermes
2. Pedirle a Hermes una tarea de refactor puntual usando `cursor_agent_code`
3. Mostrar el resultado devuelto por Cursor y compararlo con el flujo manual de `cursor-hermes-handoff` para la misma tarea

## Ejemplo real

*Pendiente* — no hemos corrido ninguno de estos tres bridges ni la skill original contra un proyecto real todavía. Se actualiza con output real una vez grabado el video.
