---
name: hermes-ag-ui-bridge
description: "Propuesta de arquitectura para exponer el estado y las acciones de Hermes Agent (mensajes en streaming, tool calls, plan/todos) a un frontend custom vía AG-UI (Agent-User Interaction Protocol), el protocolo abierto de CopilotKit para conectar agentes a interfaces React/Angular. Úsala cuando quieras construir una UI propia (chat, dashboard, panel de control) sobre una instancia de Hermes en vez de un cliente de mensajería, cuando necesites que esa UI pueda declarar herramientas invocables por el agente y recibir el resultado de vuelta, o cuando quieras entender qué eventos internos de Hermes corresponden a qué eventos de AG-UI antes de escribir el adapter tú mismo."
version: 0.1.0
author: dominicode
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [ag-ui, frontend, streaming, sse, copilotkit, protocol, bridge, ui]
    category: ag-ui
    related_skills: []
    status: proposal-not-executed
---

# Hermes AG-UI Bridge

> **Estado: propuesta de arquitectura, no ejecutada contra un Hermes real.** Este documento está
> fundamentado en el código público de dos repos verificables — [`NousResearch/hermes-agent`](https://github.com/NousResearch/hermes-agent)
> y [`ag-ui-protocol/ag-ui`](https://github.com/ag-ui-protocol/ag-ui) — y en la documentación oficial
> de AG-UI (`docs.ag-ui.com`). No es código probado en producción, no hay video, no hay output real.
> Las secciones "Pitfalls" y "Verification" existen precisamente para separar lo que está verificado
> (los nombres de eventos, la forma de `RunAgentInput`, el vocabulario de streaming que Hermes ya
> tiene en `gateway/stream_events.py`) de lo que es hipótesis razonada y sigue sin confirmar (si
> `run_agent.py` puede pausar un turno a mitad de una tool call y reanudarlo después).

## Overview

Hermes ya tiene un puente de agente-a-agente: `acp_adapter/` (usado por la skill
[`hermes-agent-acp-skill`](../../../Claude%20Code/README.md) de la categoría Claude Code) traduce el
comportamiento de Hermes al protocolo ACP para que editores como Zed puedan hablar con él. **AG-UI
es un protocolo distinto y complementario**: no conecta a Hermes con otro agente, lo conecta con un
**frontend** — un chat React, un dashboard, un panel de control — usando un vocabulario de eventos de
streaming estandarizado (`RunStarted`, `TextMessageContent`, `ToolCallStart`, `StateDelta`, etc.) en
vez de que cada proyecto invente su propio formato de WebSocket/SSE ad-hoc.

A fecha de escritura, **no existe una skill Hermes↔AG-UI publicada por la comunidad** — se buscó
explícitamente (`gh api search/repositories` y `search/code` con combinaciones de "ag-ui hermes",
"agent-user interaction protocol skill", "ag-ui SKILL.md hermes", y se inspeccionó el propio
directorio `integrations/` de `ag-ui-protocol/ag-ui`, que sí lista adaptadores para LangChain,
CrewAI, LangGraph, Claude Agent SDK, Vercel AI SDK, entre otros, pero ninguno para Hermes) y no
apareció nada real. Esta skill llena ese hueco como propuesta, no como reporte de algo ya construido.

**Contexto verificado del protocolo (julio 2026):**

| Repo | Qué es | Stars | Licencia |
|---|---|---|---|
| [`ag-ui-protocol/ag-ui`](https://github.com/ag-ui-protocol/ag-ui) | Especificación + SDKs (Python, TypeScript, .NET) de AG-UI | 14,617 | MIT |
| [`CopilotKit/CopilotKit`](https://github.com/CopilotKit/CopilotKit) | Autores de AG-UI; stack de frontend para agentes (React, Angular, mobile, Slack) | 35,834 | MIT |
| [`NousResearch/hermes-agent`](https://github.com/NousResearch/hermes-agent) | El agente que esta skill busca conectar | 211,152 | MIT |

## When to Use

- Quieres construir un **frontend propio** (chat, dashboard, panel de operador) sobre una instancia
  de Hermes, y prefieres hablar el protocolo estándar AG-UI en vez de diseñar tu propio formato de
  eventos de streaming desde cero.
- Necesitas que ese frontend pueda **declarar herramientas que el agente invoca**, y que el resultado
  vuelva al agente sin que tengas que resolver tú mismo el problema de "cómo le devuelvo esto a
  Hermes" — AG-UI ya define ese ciclo (`RunAgentInput.tools` → `ToolCallStart/Args/End` →
  ejecución en el frontend → mensaje `role: "tool"` en un nuevo `RunAgentInput`).
- Quieres reusar componentes del ecosistema CopilotKit (o cualquier otro cliente compatible con
  AG-UI) contra un backend Hermes, en vez de escribir un cliente de chat desde cero.
- Quieres entender, **antes de escribir una sola línea de adapter**, qué evento interno de Hermes
  (`gateway/stream_events.py`) corresponde a qué evento de AG-UI, y dónde la traducción no es 1:1.

**No la uses para:**

- Delegación agente-a-agente (Hermes ↔ Claude Code / Codex) — eso ya lo cubre `acp_adapter/` y la
  skill `hermes-agent-acp-skill` de la categoría Claude Code de este catálogo.
- Canales de mensajería (Telegram, Discord, Slack, WhatsApp, Signal) — Hermes ya tiene un `gateway/`
  dedicado a eso; AG-UI es para una UI web/app propia, no para un bot de chat existente.
- Si lo único que necesitas es un dashboard de administración simple, revisa primero si el `web/`
  que Hermes ya trae en su propio repo (Vite + TypeScript) te resuelve el caso antes de construir un
  bridge de protocolo nuevo.

## Procedure

### 1. Ubicar el bridge junto al patrón que Hermes ya usa para ACP

`acp_adapter/` ya resuelve el problema estructural de "traducir el runtime interno de Hermes a un
protocolo externo": tiene `server.py` (entry point del protocolo), `session.py` (mapeo de sesión),
`events.py` (traducción de callbacks de `AIAgent` a notificaciones del protocolo) y `tools.py`
(construcción de eventos de tool call). Un bridge de AG-UI es arquitectónicamente el mismo patrón,
hablando otro vocabulario — por ejemplo, un módulo hermano `agui_adapter/` con la misma forma:

```
agui_adapter/
├── server.py     # endpoint HTTP que acepta RunAgentInput y responde text/event-stream
├── session.py    # mapea thread_id/run_id (AG-UI) <-> sesión de Hermes (session_context.py)
├── events.py     # traduce gateway/stream_events.py -> eventos ag_ui.core
└── tools.py      # registra tools declaradas por el frontend como toolset transitorio del run
```

### 2. El servidor: HTTP + SSE, no WebSocket

AG-UI en su forma de referencia usa **Server-Sent Events**, no WebSocket: el cliente hace un `POST`
con un `RunAgentInput` (`thread_id`, `run_id`, `messages`, `tools`, estado) y el servidor responde con
`Content-Type: text/event-stream`, manteniendo la conexión abierta mientras emite eventos. El SDK de
Python oficial (`ag_ui.core` para los tipos de evento, `ag_ui.encoder.EventEncoder` para serializar
según el header `Accept`) es la pieza que haría ese trabajo — no hay que inventar un formato de wire
nuevo. Ver `templates/agui_adapter_skeleton.py` para un esqueleto ilustrativo de este endpoint.

### 3. Traducir eventos salientes: Hermes → AG-UI

Hermes ya separa, en `gateway/stream_events.py`, "qué pasó" (`MessageChunk`, `MessageStop`,
`Commentary`, `ToolCallChunk`, `ToolCallFinished`, `LongToolHint`, `GatewayNotice`) de "cómo se
renderiza" (decisión que hoy toma cada adaptador de plataforma en el gateway). Un bridge de AG-UI es,
en esencia, **un adaptador más de ese mismo vocabulario** — igual que Telegram o Discord tienen el
suyo, AG-UI sería otro consumidor de `StreamEvent`. La tabla completa de mapeo, con las notas de qué
sí y qué no viaja 1:1, está en `references/event-mapping.md` — resumen:

| Evento Hermes | Evento(s) AG-UI |
|---|---|
| `MessageChunk` | `TextMessageContent` |
| `MessageStop(final=False)` | `TextMessageEnd` |
| `MessageStop(final=True)` | `TextMessageEnd` + `RunFinished` |
| `Commentary` | ciclo propio `TextMessageStart` → `TextMessageContent` → `TextMessageEnd` |
| `ToolCallChunk` | `ToolCallStart` + `ToolCallArgs` |
| `ToolCallFinished` | `ToolCallEnd` (sin `ToolCallResult` — ver Pitfalls) |
| `LongToolHint` / `GatewayNotice` | `Custom` |
| resultado de la tool `todo` | `StateDelta` sobre una key `todos` (mismo parseo que `acp_adapter` ya hace para `AgentPlanUpdate`, redirigido a otro sink) |

### 4. Herramientas invocables desde la UI: la dirección inversa

Esta es la parte que el brief original pedía explícitamente y la menos intuitiva. AG-UI **no** asume
que el agente ejecuta la tool y espera el resultado en el mismo ciclo — el flujo real, confirmado
contra la documentación oficial (`docs.ag-ui.com/concepts/tools`), es **asíncrono y de dos ciclos**:
el frontend declara la tool en `RunAgentInput.tools`, el agente emite
`ToolCallStart` → `ToolCallArgs` → `ToolCallEnd` y el run **termina** (`RunFinished`) con la tool call
pendiente; el frontend la ejecuta localmente y abre un **nuevo** `RunAgentInput` (mismo `thread_id`)
con un mensaje `role: "tool"` referenciando el `toolCallId`. Detalle completo, con el paso a paso de
qué tendría que hacer el bridge en cada extremo, en `references/frontend-tools-flow.md`.

### 5. Estado compartido

Para campos que no son mensajes ni tool calls (contadores de uso, sesión activa, modo verbose —
territorio de `hermes_state.py`), `StateSnapshot` al abrir la conexión y `StateDelta` (JSON Patch
RFC 6902) para cambios incrementales son el mecanismo que AG-UI ya define para esto — no hay que
inventar un canal paralelo.

## Pitfalls

- **El ciclo de dos runs para tools de frontend no está verificado contra `run_agent.py`.** Que AG-UI
  *defina* el protocolo como asíncrono no significa que el loop interno de Hermes ya soporte "terminar
  un turno con una tool call pendiente y reanudarlo después con el resultado inyectado como si Hermes
  la hubiera ejecutado él mismo". Esto puede requerir cambios reales en Hermes, no solo un adapter
  externo — es el mayor riesgo técnico de toda esta propuesta.
- **`ToolCallResult` no tiene una fuente limpia para tools que Hermes ejecuta localmente.**
  `gateway/stream_events.py` dice explícitamente, en el docstring de `ToolCallFinished`, que "no tool
  *output* travels here — output is the agent's concern". El bridge tendría que leer el resultado de
  otra fuente (el historial de mensajes persistido del agente), lo que lo acopla a un detalle interno
  que puede cambiar sin aviso entre versiones de Hermes.
- **No hay endpoint HTTP/SSE de AG-UI en Hermes hoy.** A diferencia de activar una opción de config,
  esto es construir un servidor nuevo desde cero (`agui_adapter/server.py`), con su propio ciclo de
  vida, manejo de errores y reconexión.
- **AG-UI asume un agente por `thread_id`; el gateway de Hermes multiplexa una sesión entre varias
  plataformas simultáneamente.** Antes de escribir código hay que decidir si un thread de AG-UI es
  *otra* superficie sobre la misma sesión de Hermes o una sesión aislada — mezclarlo sin decidirlo
  explícitamente produce estado inconsistente entre lo que ve la UI y lo que ven Telegram/Discord.
- **No asumas los mismos nombres de campo en distintas versiones del SDK de AG-UI.** El proyecto está
  activo (`ag-ui-protocol/ag-ui` tuvo push el mismo día en que se escribió esta skill) — confirma los
  tipos exactos de `ag_ui.core` contra la versión que instales, no contra este documento.
- **No hay prior art que copiar.** La búsqueda en GitHub (repos y código) no encontró ninguna
  integración Hermes↔AG-UI existente — todo el mapeo de arriba es una hipótesis de diseño razonada
  sobre código público real, no un plan validado por nadie en producción todavía.

## Verification

Nada de lo siguiente se ha corrido. Es el checklist que falta, no un reporte de resultados:

1. **Servidor mínimo primero.** Levanta el `server-starter` oficial de
   `ag-ui-protocol/ag-ui/integrations/` (o el ejemplo de FastAPI de la doc de quickstart) y confírmalo
   con el cliente de referencia (`@ag-ui/client`) antes de tocar Hermes — así separas "¿mi
   entendimiento de AG-UI es correcto?" de "¿mi traducción de Hermes es correcta?".
2. **Secuencia de eventos bien formada.** Captura un log JSONL de una conversación real de Hermes
   traducida a eventos AG-UI y corre `scripts/check_event_sequence.py` contra ese log — valida que
   todo `RunStarted` cierre con `RunFinished`/`RunError`, que cada `TextMessageStart`/`ToolCallStart`
   tenga su cierre correspondiente, y que no haya IDs huérfanos.
3. **Ciclo completo de una tool de frontend.** Envía un `RunAgentInput` con una tool declarada,
   confirma `ToolCallStart`/`Args`/`End`, confirma que el run cierra, reenvía un segundo
   `RunAgentInput` con el resultado como mensaje `role: "tool"` y confirma que Hermes retoma la
   conversación usando ese contexto — no que lo trate como un mensaje de usuario nuevo.
4. **Múltiples tool calls en la misma respuesta.** Hermes puede encadenar herramientas; repite el
   punto 3 con al menos dos tool calls seguidas para confirmar que los índices de
   `ToolCallChunk`/`ToolCallFinished` no colisionan al traducirse a `toolCallId`.
5. **`skills-ref validate`** (si tu instalación de Hermes lo soporta) contra esta carpeta, para
   confirmar que el frontmatter de este `SKILL.md` sigue siendo válido si lo editas.

Actualiza esta sección — y el README de la categoría AG-UI — con resultado real una vez se ejecute
alguno de estos pasos, siguiendo el mismo criterio de honestidad que el resto del catálogo: sin
resultados de ejecución inventados.

## Reference files

- `references/event-mapping.md` — tabla extendida de mapeo `gateway/stream_events.py` ↔ eventos AG-UI,
  con los campos reales de cada dataclass y las notas de qué no es 1:1.
- `references/frontend-tools-flow.md` — el ciclo de dos runs para tools declaradas por el frontend,
  paso a paso, con lo que le tocaría hacer a cada lado (frontend / bridge / Hermes).
- `templates/agui_adapter_skeleton.py` — esqueleto ilustrativo (no ejecutado) del endpoint SSE y del
  traductor de eventos, para arrancar de un punto de partida en vez de una hoja en blanco.
- `scripts/check_event_sequence.py` — script standalone (sin dependencias de Hermes ni de AG-UI) que
  valida invariantes estructurales de un log de eventos AG-UI en JSONL.
- `assets/architecture.mmd` — diagrama Mermaid de la arquitectura propuesta.
