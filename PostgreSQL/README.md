# PostgreSQL

Skills para que Hermes Agent trabaje contra bases de datos PostgreSQL reales — las tuyas, en producción o staging, no la memoria interna del propio agente (Hermes usa SQLite por defecto para eso).

## Estado real del ecosistema

A diferencia de Next.js, Docker y Claude Code, aquí **no** encontramos una colección curada y madura de skills de PostgreSQL para agentes. La mayoría de lo que aparece buscando "postgres" en el Hub de skills es tangencial: proyectos DeFi/crypto que usan Postgres como capa de persistencia interna, un generador de skills de pago (Chion AI) que compila SKILL.md a partir de tu propia base de datos, o colecciones de stack completo (Python, Java/Spring, FastAPI) donde PostgreSQL es una de diez tecnologías cubiertas, no el foco.

Sí encontramos tres skills genuinamente específicas de Postgres, reales y con código sustancial detrás — se listan abajo. Para todo lo demás, esta categoría se inclina hacia **crear**: la skill original de esta sección (`postgres-safe-query`) cubre el caso de uso que no encontramos en ningún lado — dejar que un agente consulte una base de producción de forma segura sin exponer credenciales ni arriesgar una escritura.

## Skills recomendadas

### [`paradedb/agent-skills`](https://github.com/paradedb/agent-skills)
Skill oficial de ParadeDB (la extensión `pg_search` que trae búsqueda full-text estilo Elasticsearch — BM25, búsqueda híbrida con `pgvector`, tokenizers — directamente a Postgres). Útil si tu base ya usa o está evaluando ParadeDB, no para Postgres genérico.

### [`TechSpokes/skill-postgres-introspection`](https://github.com/TechSpokes/skill-postgres-introspection)
Enseña a un agente a construir, dentro de tu propio repo, una herramienta de introspección de solo lectura: lee los catálogos de una base viva y renderiza su estructura, seguridad (RLS, roles, grants), vistas, funciones y extensiones en archivos versionados y navegables. Metodología database-agnostic con implementación de referencia en PostgreSQL. Complementa bien a `postgres-safe-query` — introspecciona primero, consulta después.

### [`Viprasol-Tech/sql-optimizer`](https://github.com/Viprasol-Tech/sql-optimizer)
Metodología disciplinada para diagnosticar SQL lento: lee un plan `EXPLAIN ANALYZE`, encuentra el nodo más costoso, propone el índice correcto (compuesto, covering, parcial) y trae un protocolo de re-medición. Cubre PostgreSQL y MySQL. Útil una vez que `postgres-safe-query` ya te dejó ver qué query es lenta — este es el siguiente paso.

## Nivel de madurez

| Skill | Stars | Última actualización | Licencia |
|---|---|---|---|
| paradedb/agent-skills | 8 | 2026-04-30 | MIT |
| skill-postgres-introspection | 0 | 2026-06-19 | MIT |
| sql-optimizer | 0 | 2026-06-14 | MIT |

*Las dos últimas tienen 0 stars — no es una señal de calidad del código (lo revisamos y son sustanciales, con `references/`, tests y documentación real), es una señal de que casi nadie las ha probado todavía. Aplica la misma cautela que con cualquier dependencia nueva de 0 stars.*

## Skill original — creada por Dominicode

### [`postgres-safe-query`](skills/postgres-safe-query/SKILL.md)

No encontramos ninguna skill pública enfocada específicamente en dejar que un agente consulte una base de datos de **producción** de forma segura — solo lectura forzada a nivel de rol, límite de filas aplicado del lado del servidor, timeout de statement como respaldo real, y credenciales que nunca entran al contexto del modelo ni a un log. Así que la escribimos nosotros.

Qué incluye:

- **`SKILL.md`** — procedimiento completo: rol de solo lectura dedicado, manejo de credenciales, validación de queries antes de ejecutarlas, ejecución dentro de una transacción read-only con timeout, y una sección de Pitfalls con los bypass reales que un validador ingenuo deja pasar (CTEs que escriben, statements apilados, `COPY ... TO PROGRAM`, keywords ocultos con comentarios).
- **`scripts/validate_query.py`** — validador en Python puro (stdlib, sin dependencias) que rechaza cualquier cosa que no sea una única sentencia de lectura, bloquea funciones de lectura/escritura de archivos del servidor, y aplica un límite de filas del lado del servidor.
- **`scripts/run-safe-query.sh`** — wrapper de referencia que encadena el validador con `psql` dentro de una transacción `BEGIN / SET LOCAL statement_timeout / ROLLBACK`.
- **`templates/readonly-role.sql`** y **`templates/.env.example`** — el rol de Postgres y las variables de entorno de partida.
- **`references/query-validation-rules.md`** y **`references/credential-handling.md`** — el razonamiento detrás de cada regla, no solo la regla.

**Verificado hasta ahora:** el validador se corrió a mano contra ~15 casos (los ejemplos de bypass de la sección Pitfalls del propio SKILL.md, más queries normales) y rechaza/permite correctamente en todos. **No verificado todavía:** el rol de Postgres, el wrapper de `psql` y la skill completa no se han corrido contra una instancia de Hermes real ni contra una base de datos real — es un punto de partida auditable, no un binario probado en batalla. El propio `SKILL.md` deja esto explícito en su encabezado.

## Casos de uso

- Responder una pregunta de soporte ("¿por qué a este cliente le aparece el plan equivocado?") consultando la base real, sin poder tocar una fila por accidente.
- Reportes y analítica ad-hoc cuando montar una herramienta de BI completa es demasiado para la pregunta.
- Auditar la estructura real de una base (RLS, roles, grants) para documentación o una revisión de seguridad, sin necesitar la base corriendo para leer el resultado.
- Diagnosticar una query lenta con un plan `EXPLAIN ANALYZE` real y llegar a un índice concreto, en vez de a un `CREATE INDEX` a ciegas.

## Instalación

```bash
hermes skills install https://raw.githubusercontent.com/<owner>/<repo>/main/<ruta-a-la-skill>/SKILL.md --force
```

Para `postgres-safe-query`, una vez publicado este repo:

```bash
hermes skills install https://raw.githubusercontent.com/<owner>/awesome-hermes-for-developers/main/PostgreSQL/skills/postgres-safe-query/SKILL.md --force
```

`paradedb/agent-skills` trae un único `SKILL.md` en la raíz del repo. `skill-postgres-introspection` y `sql-optimizer` también — revisa igual el README de cada uno antes de instalar, por si el path cambia entre versiones.

## Vídeo demostración

*Pendiente de grabar.* Guion propuesto (3-4 min):
1. Crear el rol `hermes_readonly` con `templates/readonly-role.sql` contra una base de prueba con datos realistas.
2. Instalar `postgres-safe-query` en una instancia de Hermes real y pedirle una pregunta de soporte típica.
3. Mostrar un intento deliberado de bypass (un CTE que escribe, un statement apilado) y cómo el validador lo rechaza antes de tocar la base.
4. Mostrar el límite de filas y el timeout actuando sobre una query real sin `WHERE`.

## Ejemplo real

*Pendiente* — no hemos corrido `postgres-safe-query` contra un Hermes real conectado a una base de datos de verdad todavía. Se actualiza con output real (rechazos y resultados reales, no inventados) una vez grabado el video.
