# Protocolo de handoff por archivos — referencia

Este documento describe el formato completo. `SKILL.md` cubre el flujo de
uso; esto es la especificación de soporte.

## Layout de directorio

```
.hermes-cursor-handoff/
├── pending/       # tareas creadas, esperando que alguien las tome
├── in_progress/   # opcional: algunos setups mueven el archivo aquí al tomarlo
├── done/          # pares task.md + result.md con status: done
└── failed/        # pares task.md + result.md con status: failed
```

`in_progress/` es opcional — muchos setups simples se saltan este paso y
solo cambian el campo `status` dentro del propio archivo en `pending/`
mientras trabajan, moviéndolo recién al terminar. Usa el directorio físico
`in_progress/` solo si tienes más de un receptor potencial y necesitas que
el rename (mover el archivo) sea la señal atómica de "esto ya lo tomé".

## Naming convention

```
<timestamp-ISO-sin-dos-puntos>-<slug-corto>.task.md
<timestamp-ISO-sin-dos-puntos>-<slug-corto>.result.md
```

Ejemplo: `2026-07-08T14-32-00-refactor-auth-middleware.task.md`

El `id` dentro del frontmatter debe coincidir exactamente con este prefijo
(sin la extensión) — es lo que usan los scripts para emparejar
task ↔ result.

## Frontmatter — task

| Campo | Tipo | Obligatorio | Descripción |
|---|---|---|---|
| `id` | string | sí | Debe coincidir con el nombre de archivo sin extensión |
| `from` | `hermes` \| `cursor` | sí | Quién delega |
| `to` | `hermes` \| `cursor` | sí | Quién debe ejecutar |
| `status` | `pending` \| `in_progress` \| `done` \| `failed` | sí | Estado actual |
| `created_at` | ISO-8601 | sí | Momento de creación |
| `repo_path` | string | sí | Ruta relativa al repo (normalmente `.`) |
| `branch` | string | no | Rama sobre la que trabajar, si no es la actual |

## Frontmatter — result

| Campo | Tipo | Obligatorio | Descripción |
|---|---|---|---|
| `task_id` | string | sí | Debe coincidir con el `id` del task correspondiente |
| `status` | `done` \| `failed` | sí | Resultado final |
| `completed_at` | ISO-8601 | sí | Momento de finalización |
| `files_changed` | lista de strings | no | Rutas de archivos modificados |
| `diff_ref` | string | no | SHA de commit o ruta a un archivo `.patch` |

## Ciclo de vida

```
pending → (in_progress) → done
                        → failed
```

No hay transición de vuelta a `pending` — si una tarea falla y quieres
reintentarla, crea un nuevo `id` (mismo contenido, timestamp nuevo) en vez
de reabrir el original. Esto mantiene el historial en `failed/` intacto
como registro de qué no funcionó la primera vez.

## Por qué no hay un campo `priority` o `assignee` con nombre de usuario

Esta skill asume que solo hay dos partes en la conversación: un Hermes y un
Cursor (o instancias de ambos). Si tu setup involucra más de dos agentes o
necesitas colas con prioridad, este protocolo de archivos planos deja de
ser suficiente — en ese punto conviene migrar a uno de los bridges MCP/ACP
reales listados en el `README.md` de la categoría, que sí tienen un canal
de comunicación estructurado.

## Limpieza

No hay expiración automática. Sugerencia de mantenimiento manual (o vía
cron, fuera del alcance de esta skill):

```bash
# Archivar (o borrar) tareas en done/failed con más de 30 días
find .hermes-cursor-handoff/done .hermes-cursor-handoff/failed \
  -name '*.task.md' -mtime +30 -print
```
