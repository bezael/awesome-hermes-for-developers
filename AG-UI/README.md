# AG-UI

Puente entre Hermes Agent y [AG-UI](https://ag-ui.com) (Agent-User Interaction Protocol) — el
protocolo abierto de [CopilotKit](https://github.com/CopilotKit/CopilotKit) para conectar agentes de
IA a interfaces de usuario (React, Angular, mobile, Slack...). No es una skill "sobre" AG-UI, es un
puente real entre Hermes y ese protocolo, para exponer streaming de eventos y herramientas invocables
desde un frontend propio.

## Qué es AG-UI (contexto, no una skill)

AG-UI no es un producto de Hermes ni de Dominicode — es un protocolo de terceros, real y con tracción
propia, verificado directamente contra la API de GitHub al momento de escribir esto:

| Repo | Qué es | Stars | Última actividad | Licencia |
|---|---|---|---|---|
| [`ag-ui-protocol/ag-ui`](https://github.com/ag-ui-protocol/ag-ui) | Especificación del protocolo + SDKs (Python, TypeScript, .NET) | 14,617 | 2026-07-07 | MIT |
| [`CopilotKit/CopilotKit`](https://github.com/CopilotKit/CopilotKit) | Autores de AG-UI; stack de frontend para agentes | 35,834 | 2026-07-08 | MIT |

AG-UI define un vocabulario estandarizado de eventos de streaming (`RunStarted`, `TextMessageContent`,
`ToolCallStart`, `StateDelta`, etc.) transportados por SSE, para que un frontend no tenga que hablar
un formato ad-hoc distinto con cada backend de agente. El propio repo oficial ya tiene adaptadores
para LangChain, CrewAI, LangGraph, Claude Agent SDK, Vercel AI SDK, Mastra, AWS Strands y varios más
(carpeta `integrations/` de `ag-ui-protocol/ag-ui`) — pero ninguno para Hermes.

## No existe (todavía) una skill Hermes↔AG-UI de la comunidad

Se buscó explícitamente antes de escribir esta categoría — `gh api search/repositories` y
`search/code` con combinaciones de "ag-ui hermes", "hermes-agent ag-ui", "agent-user interaction
protocol skill", "ag-ui SKILL.md hermes" — y también se inspeccionó a mano la carpeta `integrations/`
del propio repo de AG-UI. No apareció ningún resultado real: ni una skill publicada, ni un adaptador,
ni una mención cruzada entre ambos proyectos. Esta categoría es **100% "crear", no "curar"** — no hay
nada existente que recomendar, así que en vez de dejarla vacía escribimos la skill que falta.

## Skill original de Dominicode

### [`hermes-ag-ui-bridge`](skills/hermes-ag-ui-bridge/SKILL.md)
Propuesta de arquitectura para exponer el estado de Hermes (mensajes en streaming, tool calls,
plan/todos) y sus acciones a un frontend vía AG-UI — con el mapeo detallado de qué evento interno de
Hermes (`gateway/stream_events.py`) corresponde a qué evento de AG-UI, y cómo funcionaría el ciclo de
herramientas invocables desde la UI (que en AG-UI es asíncrono, de dos ciclos de request/response, no
una llamada bloqueante). **Es ilustrativa: no se ha ejecutado todavía contra un Hermes real ni contra
un cliente AG-UI real.** Ver la sección "Pitfalls" del propio `SKILL.md` para los riesgos técnicos sin
verificar (el más grande: si el loop de `run_agent.py` puede pausar un turno a mitad de una tool call
de frontend y reanudarlo con el resultado inyectado después).

## Nivel de madurez

| Elemento | Stars | Última actualización | Licencia |
|---|---|---|---|
| Protocolo AG-UI (`ag-ui-protocol/ag-ui`) | 14,617 | 2026-07-07 | MIT |
| `hermes-ag-ui-bridge` (original, esta skill) | — (no publicada como repo propio, vive aquí) | 2026-07-08 | MIT |

*A diferencia de otras categorías de este catálogo, aquí no hay una skill de terceros que auditar —
la única pieza nueva es la que escribimos nosotros, y por eso el nivel de madurez real es "diseño
razonado, cero horas de ejecución", no un número de stars.*

## Casos de uso

- Construir un frontend propio (chat, dashboard, panel de operador) sobre una instancia de Hermes en
  vez de depender de un cliente de mensajería (Telegram/Discord/Slack, que ya cubre el `gateway/`
  nativo de Hermes).
- Declarar herramientas del lado del frontend que el agente pueda invocar, con el resultado volviendo
  de forma nativa al protocolo en vez de inventar un canal paralelo.
- Reusar componentes del ecosistema CopilotKit (o cualquier otro cliente compatible con AG-UI) contra
  un backend Hermes.
- Entender, antes de escribir el adapter, exactamente qué evento de `gateway/stream_events.py` mapea
  a qué evento de AG-UI — y dónde ese mapeo no es 1:1 (ver `references/event-mapping.md` de la skill).

## Instalación

```bash
hermes skills install https://raw.githubusercontent.com/bezael/awesome-hermes-for-developers/main/AG-UI/skills/hermes-ag-ui-bridge/SKILL.md --force
```

`--force` es necesario porque es una skill de trust level `community` (no oficial de Nous Research).
Como es una skill de este catálogo y no de un repo externo de una sola skill, también puedes instalarla
directo desde una copia local del repo:

```bash
hermes skills install ./AG-UI/skills/hermes-ag-ui-bridge/SKILL.md --force
```

## Vídeo demostración

*Pendiente de grabar.* Guion propuesto (4-5 min, el más largo del catálogo porque hay que mostrar
protocolo, no solo un comando):

1. Levantar el `server-starter` oficial de `ag-ui-protocol/ag-ui/integrations/` y validarlo con el
   cliente de referencia (`@ag-ui/client`), para separar "¿entiendo bien AG-UI?" de "¿mi bridge de
   Hermes está bien?".
2. Mostrar el mapeo de eventos en vivo: disparar una conversación en Hermes y ver, lado a lado, el
   evento nativo de `gateway/stream_events.py` y el evento AG-UI equivalente.
3. Declarar una tool desde el frontend, verla invocada por Hermes, y mostrar el segundo
   `RunAgentInput` que devuelve el resultado — el punto que más cuesta explicar solo con texto.
4. Correr `scripts/check_event_sequence.py` de la skill contra el log capturado del paso 2 y mostrar
   que pasa (o, más honesto todavía, mostrar qué reporta cuando falla algo a propósito).

## Ejemplo real

*Pendiente* — no hemos corrido este bridge contra un proyecto real todavía. A diferencia del resto
del catálogo (donde "pendiente" significa "no hemos probado la skill de alguien más"), aquí también
significa "el código del bridge en sí no existe fuera de los esqueletos ilustrativos en
`templates/`". Se actualiza con output real una vez se construya y se grabe el video de arriba.
