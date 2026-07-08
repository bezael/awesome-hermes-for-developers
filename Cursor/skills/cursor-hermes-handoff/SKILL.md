---
name: cursor-hermes-handoff
description: Delega una tarea de refactor puntual entre Hermes Agent y Cursor usando un protocolo de archivos compartidos (task/result), sin depender de MCP ni ACP. Sirve como fallback ligero cuando no tienes un bridge en tiempo real instalado, o como primer paso antes de instalar uno.
version: 0.1.0
license: MIT
platforms:
  - hermes
  - cursor
metadata:
  hermes:
    category: cursor
    tags:
      - handoff
      - delegation
      - refactor
      - file-based
      - cursor
      - multi-agent
      - fallback
    author: Dominicode
    status: illustrative-not-yet-run-against-real-hermes
---

# cursor-hermes-handoff

> **Estado:** skill original de Dominicode, escrita para este catálogo. Es **ilustrativa** — el protocolo de archivos y los scripts se probaron localmente (ver "Verification" abajo), pero **no se ha ejecutado aún contra una instancia real de Hermes Agent** ni contra una sesión real de Cursor. Trátala como un borrador funcional, no como una skill validada en producción.

## Por qué existe

Los bridges reales entre Cursor y Hermes que encontramos (`tommulkins/cursor-hermes-bridge`, `nirvana6/hermes-mcp-bridge`, `Cosmic-Construct/hermes-cursor-harness`) requieren infraestructura: registrar un servidor MCP en Hermes, tener `cursor-agent` instalado y logueado, o correr un gateway HTTP local. Eso es lo correcto cuando quieres una integración en tiempo real.

Pero muchas veces solo necesitas delegar **una tarea puntual** — "Cursor, refactoriza este módulo mientras yo sigo con otra cosa en Hermes" — sin instalar ni configurar nada nuevo. `cursor-hermes-handoff` resuelve eso con el patrón más simple que existe: **archivos compartidos en el propio repo**, el mismo patrón que ya usan las skills puente de la categoría Claude Code de este catálogo.

## When to Use

- Necesitas que Cursor haga un refactor, migración o limpieza de código puntual mientras Hermes sigue trabajando en otra tarea (o viceversa).
- No tienes (o no quieres instalar todavía) un bridge MCP/ACP en tiempo real entre Hermes y Cursor.
- Quieres un rastro auditable en disco de qué se delegó, quién lo hizo y qué resultó — útil en repos donde varias personas/agentes tocan el mismo código.
- Trabajas en un entorno donde Hermes y Cursor comparten el mismo filesystem (misma máquina, mismo repo montado, o un volumen sincronizado) pero no necesariamente la misma sesión interactiva.

**No uses esta skill si** necesitas streaming de progreso en vivo, sesiones persistentes con memoria de conversación entre turnos, o control remoto de Cursor desde Hermes — para eso instala uno de los bridges MCP/ACP reales listados en el `README.md` de esta categoría.

## Procedure

### 1. Preparar el directorio de handoff

En la raíz del repo compartido:

```bash
mkdir -p .hermes-cursor-handoff/{pending,done,failed}
echo ".hermes-cursor-handoff/" >> .gitignore
```

Ver `references/handoff-protocol.md` para el layout completo y el porqué de cada carpeta.

### 2. El agente que delega crea un archivo de tarea

Copia `templates/task.hermes-handoff.md`, complétalo y guárdalo como
`.hermes-cursor-handoff/pending/<timestamp>-<slug>.task.md`.

Ejemplo mínimo (Hermes delegando a Cursor):

```markdown
---
id: 2026-07-08T14-32-00-refactor-auth-middleware
from: hermes
to: cursor
status: pending
created_at: 2026-07-08T14:32:00Z
repo_path: .
branch: main
---

## Tarea

Refactoriza `src/middleware/auth.ts` para usar async/await en vez de
callbacks anidados. No cambies la firma pública del middleware.

## Contexto

- Archivo: src/middleware/auth.ts
- Tests relevantes: src/middleware/__tests__/auth.test.ts (deben seguir pasando)

## Criterio de aceptación

- `pnpm test src/middleware/auth.test.ts` pasa
- Sin callbacks anidados de más de 2 niveles
```

`scripts/new-task.sh` automatiza este paso (genera el id, el timestamp y el nombre de archivo por ti).

### 3. El agente receptor recoge la tarea

Quien recibe (un humano operando Cursor, o Hermes en un loop) revisa
`.hermes-cursor-handoff/pending/*.task.md` filtrando por `to: <su-nombre>`,
mueve el archivo a `in_progress` (cambiando el campo `status` en el
frontmatter) y empieza a trabajar.

`scripts/watch-handoff.sh` implementa el polling: corre en segundo plano y
notifica (imprime a stdout) cada vez que aparece una tarea nueva dirigida a
un destinatario específico, o cuando cambia el estado de una ya existente.

```bash
./scripts/watch-handoff.sh --to cursor --dir .hermes-cursor-handoff
```

### 4. El agente receptor escribe el resultado

Al terminar (o al fallar), copia `templates/result.hermes-handoff.md`,
complétalo y guárdalo junto al task original con el mismo slug pero
extensión `.result.md`. Luego mueve el par `task.md` + `result.md` a
`done/` o `failed/` según corresponda (`scripts/complete-task.sh` hace
ambas cosas en un solo paso).

```bash
./scripts/complete-task.sh \
  --id 2026-07-08T14-32-00-refactor-auth-middleware \
  --status done \
  --summary "Refactorizado a async/await, 3 archivos cambiados" \
  --files "src/middleware/auth.ts,src/middleware/__tests__/auth.test.ts"
```

### 5. El agente que delegó recoge el resultado

Vuelve a consultar `.hermes-cursor-handoff/done/` (o `failed/`) buscando el
`id` que le interesa, lee el `.result.md` e integra el resumen a su propio
contexto/memoria. Si el resultado incluye un `diff_ref` (SHA de commit o
ruta a un `.patch`), aplícalo o revísalo antes de darlo por bueno — este
protocolo **no** aplica cambios de código por ti, solo coordina quién hizo
qué.

## Pitfalls

- **Carrera entre dos receptores.** Si Hermes corre en loop y un humano
  también revisa `pending/` a mano, ambos pueden intentar tomar la misma
  tarea. Usa `scripts/watch-handoff.sh` (que hace un rename atómico a
  `in_progress` antes de notificar) en vez de leer `pending/` directamente
  con `ls`/`cat`.
- **Archivos huérfanos.** Una tarea que nadie recoge se queda en `pending/`
  para siempre — no hay expiración automática. Revisa `pending/` de vez en
  cuando o agrega tu propio cron que archive tareas con más de N días.
- **Esto no ejecuta código por ti.** El protocolo coordina la delegación y
  el reporte, pero no dispara `cursor-agent` ni ninguna API de Hermes
  automáticamente. Si quieres ese nivel de automatización, esta skill es un
  buen primer paso, pero termina instalando uno de los bridges MCP/ACP
  reales de este catálogo.
- **Rutas relativas vs. absolutas.** `repo_path` en el task file asume que
  ambos agentes tienen el mismo repo montado en una ruta accesible. En
  setups distribuidos (Hermes en un VPS, Cursor en tu laptop) necesitas
  sincronizar el directorio `.hermes-cursor-handoff/` por separado (git,
  rsync, o una carpeta compartida) — este protocolo no resuelve la
  sincronización de archivos entre máquinas distintas, solo el formato de
  coordinación una vez que el directorio es visible para ambos.
- **No confundas `status: done` con "aceptado".** Que el receptor marque
  `done` solo significa que terminó su parte. Sigue siendo responsabilidad
  del que delegó revisar el resultado antes de mergear o cerrar la tarea
  original.

## Verification

Lo que sí se verificó localmente (filesystem puro, sin Hermes ni Cursor
reales de por medio):

- `scripts/new-task.sh` crea un archivo con el frontmatter y el nombre de
  archivo esperados en `pending/`.
- `scripts/watch-handoff.sh` detecta un archivo nuevo en `pending/` y lo
  reporta una sola vez (no repite notificaciones en cada poll).
- `scripts/complete-task.sh` mueve correctamente el par `task.md` +
  `result.md` a `done/` o `failed/` según el flag `--status`.

Lo que **no** se verificó (pendiente, requiere una instancia real):

- Que un Hermes Agent real sepa interpretar `templates/task.hermes-handoff.md`
  sin instrucciones adicionales en su propio prompt/config.
- Que un humano operando Cursor encuentre el flujo cómodo en la práctica
  (esto es un protocolo de archivos, no un plugin de Cursor con UI).
- Latencia real de punta a punta en un caso de uso concreto.

Antes de confiar en esta skill para un caso real: corre los tres scripts
tal como están (no requieren red ni credenciales), léelos completos — son
menos de 60 líneas cada uno — y ajusta los nombres de estado (`pending`,
`in_progress`, `done`, `failed`) a lo que tu propio setup de Hermes ya usa
si tienes una convención distinta.
