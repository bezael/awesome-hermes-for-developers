# FastAPI

Skills para que Hermes Agent trabaje sobre APIs FastAPI con criterio de arquitectura,
validación y manejo de errores — no solo autocompletado de rutas.

## Aclaración honesta sobre esta categoría

El ecosistema de skills específicas de FastAPI (formato `SKILL.md`/agentskills.io) es
todavía delgado comparado con Next.js o Docker — la mayoría de lo que existe son
toolkits de Python más amplios (Django, SQLAlchemy, pytest...) que incluyen FastAPI como
una pieza más, no colecciones dedicadas 100% a FastAPI. Por eso esta categoría combina
dos cosas:

1. **Skills recomendadas de la comunidad** — lo poco (pero real) que encontramos.
2. **Una skill original de Dominicode** (`fastapi-endpoint-review`) — la escribimos
   nosotros porque no encontramos una skill de terceros enfocada específicamente en
   revisar un endpoint nuevo contra buenas prácticas de Pydantic/errores/DI/OpenAPI.
   Está marcada explícitamente como original más abajo — no es un repo de terceros.

## Skills recomendadas (de la comunidad)

### [`dm1tryG/fastapi-to-skill`](https://github.com/dm1tryG/fastapi-to-skill)
Caso de uso distinto al resto de esta lista: no es una skill para *escribir* FastAPI,
sino un CLI (`pip install fastapi-to-skill`) que convierte cualquier app FastAPI
existente en un `SKILL.md` + CLI Typer, para que *otros* agentes puedan descubrir y
llamar tu API como si fuera una skill. Lee el spec OpenAPI que FastAPI ya genera
(`app.openapi()`) y no necesita servidor MCP ni infraestructura adicional.

### [`fastapi-practices/skills`](https://github.com/fastapi-practices/skills)
Skill (`fba`) atada al convenio arquitectónico propio del proyecto
[FastAPI Best Architecture](https://fastapi-practices.github.io/fastapi_best_architecture_docs/):
capas API/Schema/Service/CRUD/Model, convenciones de nombres, paginación, caché, Celery
e i18n. Útil sobre todo si tu proyecto ya sigue (o va a adoptar) ese framework
específico — no es agnóstica de arquitectura.

### [`vstorm-co/production-stack-skills`](https://github.com/vstorm-co/production-stack-skills)
Pack de 10 skills de "ingeniero de producción senior" que cubre más que FastAPI
(PostgreSQL, Docker, deployment, seguridad, monitoreo). La skill `production-fastapi`
puntual documenta patrones de `lifespan`, logging estructurado, health checks, shutdown
graceful, middleware, Pydantic v2 y hardening de seguridad — con checklist y templates
propios. Más orientada a *arrancar y operar* la app; nuestra skill original de abajo es
más específica a *revisar un endpoint puntual* antes de mergear.

### [`manikosto/claude-code-python-stack`](https://github.com/manikosto/claude-code-python-stack)
Toolkit de Python más amplio (20 skills: Django, SQLAlchemy, pytest, Redis, Docker...)
que incluye `fastapi-patterns` y `pydantic-patterns` entre sus piezas — útil si tu stack
combina FastAPI con ese resto de herramientas, menos si solo te interesa FastAPI.

## Nivel de madurez

| Skill | Stars | Última actualización | Licencia |
|---|---|---|---|
| fastapi-to-skill | 4 | 2026-05-07 | MIT |
| fastapi-practices/skills | 10 | 2026-06-21 | MIT |
| production-stack-skills | 22 | 2026-04-16 | MIT |
| claude-code-python-stack | 42 | 2026-03-25 | Sin licencia declarada en GitHub |

*`claude-code-python-stack` es la de más estrellas del lote, pero no declara licencia
— confirma los términos con el autor antes de redistribuir su contenido en algo que no
sea experimentación personal. Ninguna de las cuatro ha sido auditada línea por línea por
este proyecto.*

## Casos de uso

- Exponer tu propia API FastAPI como una skill que otro agente pueda descubrir y llamar
  (`fastapi-to-skill`)
- Mantener consistencia arquitectónica (capas API/Service/CRUD) en un proyecto que ya
  sigue el convenio de FastAPI Best Architecture (`fastapi-practices/skills`)
- Aplicar hardening de producción (logging, health checks, shutdown graceful, seguridad)
  al levantar una app nueva (`production-stack-skills`)
- Revisar un endpoint puntual recién escrito o modificado contra validación Pydantic,
  manejo de errores HTTP, inyección de dependencias y documentación OpenAPI, antes de
  mergear (`fastapi-endpoint-review` — nuestra skill original, ver abajo)

## Instalación

```bash
# Colecciones de terceros — revisa la ruta exacta de cada skill en su repo
hermes skills install https://raw.githubusercontent.com/<owner>/<repo>/main/<ruta-a-la-skill>/SKILL.md --force

# fastapi-to-skill no se instala como skill de Hermes: es un paquete de PyPI
pip install fastapi-to-skill
fastapi-to-skill generate main:app
```

`--force` es necesario porque son skills de la comunidad (trust level `community`), no
oficiales. Si el `SKILL.md` no trae `name:` en el frontmatter, agrega `--name <alias>`.

---

## Skill original — creada por Dominicode

> **No es un repo de terceros.** `fastapi-endpoint-review` la escribimos nosotros para
> este catálogo, precisamente porque el punto anterior confirma que no hay una skill de
> comunidad enfocada en *revisar un endpoint contra buenas prácticas* (las que existen
> son plantillas de arquitectura o packs de arranque de producción). Vive en
> [`FastAPI/skills/fastapi-endpoint-review/`](./skills/fastapi-endpoint-review/) dentro
> de este mismo repo.

### [`fastapi-endpoint-review`](./skills/fastapi-endpoint-review/)

Revisa un endpoint FastAPI nuevo o modificado en cuatro frentes: validación Pydantic
(modelos explícitos, constraints de campo, `response_model` que no filtra datos
sensibles), manejo de errores HTTP (`HTTPException` con el `status.*` correcto, nada de
`except` amplios que devuelvan 200 silenciosamente), inyección de dependencias
(`Depends`, dependencias `yield` para cleanup, nada de I/O bloqueante dentro de
`async def`) y documentación OpenAPI (`summary`, `tags`, respuestas no-2xx
documentadas).

```
skills/fastapi-endpoint-review/
├── SKILL.md                          # When to Use / Procedure / Pitfalls / Verification
├── references/
│   ├── pydantic-validation.md
│   ├── error-handling.md
│   ├── dependencies.md
│   └── openapi-docs.md
├── templates/
│   └── review-checklist.md           # checklist que Hermes llena por cada endpoint
├── scripts/
│   └── check_endpoint.py             # pasada estática (AST) — sin dependencias externas
└── assets/
    ├── example_endpoint_before.py    # endpoint con los anti-patrones a propósito
    └── example_endpoint_after.py     # el mismo endpoint con las correcciones aplicadas
```

`scripts/check_endpoint.py` es un script real que corrimos nosotros mismos contra los
dos archivos de `assets/` para verificar que funciona (no es un output inventado):

```bash
$ python scripts/check_endpoint.py assets/example_endpoint_before.py assets/example_endpoint_after.py
assets/example_endpoint_before.py:
  line 21 [create_order] missing response_model= on the route decorator
  line 21 [create_order] no docstring and no summary= - route is undocumented in /docs
  line 25 [create_order] blocking call time.sleep(...) inside async def - blocks the event loop
  line 26 [create_order] blocking call requests.get(...) inside async def - blocks the event loop
  line 28 [create_order] bare/broad except with no raise - may silently swallow errors
assets/example_endpoint_after.py: OK - no mechanical findings (still do the semantic review in SKILL.md)
```

Eso sí: **este output es de correr el script en un checkout local, no de una sesión real
de Hermes.** No hemos instalado ni ejecutado esta skill contra un agente Hermes de
verdad todavía — lo que ves arriba prueba que el checker funciona, no que la skill
completa (procedimiento + checklist + agente decidiendo qué hacer con los hallazgos) se
haya validado en un caso real.

### Instalación

```bash
hermes skills install https://raw.githubusercontent.com/bezael/awesome-hermes-for-developers/main/FastAPI/skills/fastapi-endpoint-review/SKILL.md --force --name fastapi-endpoint-review
```

## Vídeo demostración

*Pendiente de grabar.* Guion propuesto (2-3 min):
1. Instalar `fastapi-endpoint-review` en una instancia de Hermes real
2. Pedirle a Hermes que revise `assets/example_endpoint_before.py` (o un endpoint real
   del proyecto) contra la skill
3. Mostrar el checklist completado y compararlo con la versión corregida en
   `assets/example_endpoint_after.py`

## Ejemplo real

*Pendiente* — no hemos corrido `fastapi-endpoint-review` (ni ninguna de las skills de
la comunidad listadas arriba) contra un agente Hermes real todavía. Se actualiza con
output real una vez grabado el video.
