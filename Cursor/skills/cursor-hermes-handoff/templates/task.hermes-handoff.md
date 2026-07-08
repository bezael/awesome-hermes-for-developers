---
id: <YYYY-MM-DDTHH-MM-SS>-<slug-corto>
from: hermes            # o "cursor" — quién delega
to: cursor               # o "hermes" — quién debe ejecutar
status: pending           # pending | in_progress | done | failed
created_at: <ISO-8601>
repo_path: .              # ruta relativa al repo, asumida igual en ambos lados
branch: main
---

## Tarea

<Describe la tarea en 2-5 líneas. Sé específico: qué archivo(s), qué
comportamiento debe cambiar y qué debe seguir igual.>

## Contexto

- Archivo(s) relevante(s):
- Tests relevantes (si aplica):
- Decisiones ya tomadas que el receptor no debería revisitar:

## Criterio de aceptación

- <Cómo sabe el receptor que terminó> (ej. "el test X pasa", "el lint no
  reporta errores nuevos")
