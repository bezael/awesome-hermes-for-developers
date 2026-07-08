---
task_id: <id-del-task-correspondiente>
status: done             # done | failed
completed_at: <ISO-8601>
files_changed:
  - <ruta/archivo1>
  - <ruta/archivo2>
diff_ref:                 # opcional: SHA de commit o ruta a un .patch
---

## Resumen

<Qué se hizo, en 2-4 líneas. Si falló, explica por qué y qué haría falta
para retomarlo.>

## Notas para quien delegó

<Cualquier decisión que tomaste sobre la marcha y que el que delegó debería
conocer antes de aceptar el resultado — trade-offs, deuda técnica
introducida, tests que no corriste, etc.>
