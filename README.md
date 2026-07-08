# Awesome Hermes for Developers

Un catálogo curado de [Skills](https://agentskills.io) para [Hermes Agent](https://github.com/NousResearch/hermes-agent), organizado por stack tecnológico — no por caso de uso genérico.

> 9 categorías activas. Cada una se investigó y escribió por separado — algunas curan skills reales de la comunidad, otras son skills originales de Dominicode donde el ecosistema todavía no tenía nada específico.

## Categorías

| Categoría | Contenido |
|---|---|
| [FastAPI](./FastAPI/) | Curada + skill original |
| [AWS](./AWS/) | Curada + skill original |
| [Azure](./Azure/) | Curada + skill original |
| [PostgreSQL](./PostgreSQL/) | Curada + skill original |
| [Cursor](./Cursor/) | Curada + skill original |
| [Claude Code](./Claude%20Code/) | Curada |
| [Codex](./Codex/) | Curada + skill original |
| [MCP](./MCP/) | Curada + skill original |
| [AG-UI](./AG-UI/) | 100% skill original (no existe nada de la comunidad todavía) |

## Cómo funciona este repo

Por cada categoría vas a encontrar:

- **Skills recomendadas** — repos reales, verificados a fecha de redacción (existen, tienen licencia, no están abandonados hace años)
- **Nivel de madurez** — stars, última actualización, licencia. *No* es una nota de calidad: nadie de este proyecto ha probado el 100% del código de cada skill todavía
- **Casos de uso** — qué resuelve, según lo que la propia skill declara
- **Instalación** — el comando real de Hermes para instalarla
- **Vídeo demostración** — guion listo para grabar (todavía no grabado)
- **Ejemplo real** — marcado explícitamente como pendiente hasta que alguien la corra de verdad

## Política de honestidad

- No inventamos comandos, nombres de skills, ni resultados de ejecución.
- Si algo no está verificado (una skill no probada, un video no grabado), lo decimos — no lo rellenamos para que se vea completo.
- Instalar cualquier skill de un repo de terceros implica el mismo riesgo que instalar cualquier dependencia de código abierto: revisa el código antes de darle acceso a tu servidor. El propio Hub de Hermes marca estos repos como trust level `community`.

## Origen

Este catálogo nace del kit gratuito de [Hermes Agent en Dominicode](https://www.dominicode.com/hermes-agent) — la chuleta de comandos CLI y la config de hardening para desplegarlo en tu VPS.
