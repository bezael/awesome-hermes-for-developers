# Mapeo de eventos: `gateway/stream_events.py` (Hermes) ↔ AG-UI

Fuente de la columna Hermes: código público de `NousResearch/hermes-agent`, módulo
`gateway/stream_events.py` (confirmado por lectura directa del archivo, julio 2026). Fuente de la
columna AG-UI: `docs.ag-ui.com/concepts/events` y el propio repo `ag-ui-protocol/ag-ui`.

Este documento existe para que quien escriba `agui_adapter/events.py` no tenga que releer ambos
repos desde cero — pero **sigue siendo una propuesta de traducción, no una implementación
verificada**. Los campos de Hermes son reales (transcritos de las dataclasses); la columna "AG-UI
propuesto" es la parte de diseño de esta skill.

## Vocabulario completo de `StreamEvent` en Hermes

Hermes define un `Union` explícito de siete dataclasses frozen (deliberadamente simples: "no
behavior, no platform knowledge, no I/O", según el propio docstring del módulo):

```python
StreamEvent = Union[
    MessageChunk,
    MessageStop,
    Commentary,
    ToolCallChunk,
    ToolCallFinished,
    LongToolHint,
    GatewayNotice,
]
```

## Tabla de mapeo

### Texto del asistente

| Hermes | Campos | AG-UI propuesto | Nota |
|---|---|---|---|
| `MessageChunk` | `text: str` | `TextMessageContent(message_id, delta=text)` | AG-UI requiere un `TextMessageStart(message_id)` antes del primer delta de cada mensaje. Hermes no emite ese "start" como evento separado — el bridge debe sintetizarlo la primera vez que ve un `MessageChunk` tras un `MessageStop` (o tras el inicio del turno). |
| `MessageStop(final: bool = False)` | `final` | `TextMessageEnd(message_id)`; si `final=True`, además `RunFinished(thread_id, run_id)` | Hermes distingue "se cerró este segmento de texto porque viene una tool call" (`final=False`) de "se cerró el turno completo" (`final=True`). AG-UI no tiene un concepto directo de "segmento intermedio de turno" fuera de abrir/cerrar mensajes — el bridge debe tratar cada segmento como un mensaje AG-UI distinto y reservar `RunFinished` solo para el cierre real. |
| `Commentary(text: str)` | texto ya completo (no es delta) | Ciclo propio: `TextMessageStart(new_id)` → `TextMessageContent(delta=text)` → `TextMessageEnd(new_id)` | Es un mensaje interino completo entre iteraciones de tool call (ej. "Voy a revisar el repo primero."). Se renderiza como burbuja separada — mismo criterio que ya aplica el gateway nativo de Hermes para Telegram/Discord. |

### Tool calls

| Hermes | Campos | AG-UI propuesto | Nota |
|---|---|---|---|
| `ToolCallChunk` | `tool_name: str`, `preview: Optional[str]`, `args: Optional[Dict]`, `index: int` (monotónico por turno) | `ToolCallStart(tool_call_id=str(index), tool_call_name=tool_name)` seguido de `ToolCallArgs(tool_call_id=str(index), delta=json.dumps(args))` | AG-UI espera argumentos como *fragmentos* streameados según el modelo los genera. Hermes ya entrega `args` completo en un solo evento (no delta) — el bridge puede emitir un único `ToolCallArgs` con el JSON completo en vez de trocearlo artificialmente; es una simplificación honesta, no una limitación de Hermes. |
| `ToolCallFinished` | `tool_name: str`, `duration: float`, `ok: bool`, `index: int` | `ToolCallEnd(tool_call_id=str(index))` | **El output de la tool no viaja en este evento.** El docstring de Hermes lo dice explícitamente: "No tool *output* travels here — output is the agent's concern and is persisted to history, not streamed as presentation." `ToolCallResult` de AG-UI (que sí lleva el output) necesitaría leer ese dato de otra fuente — ver `frontend-tools-flow.md` y la sección Pitfalls del `SKILL.md` principal. |

### Control / lifecycle de la gateway

| Hermes | Campos | AG-UI propuesto | Nota |
|---|---|---|---|
| `LongToolHint` | `tool_name: str`, `duration: float` | `Custom(name="long_tool_hint", value={...})` | Nudge de onboarding específico de la gateway de mensajería (sugerir `/verbose`); no tiene equivalente semántico en AG-UI. `Custom` es exactamente el escape hatch que AG-UI reserva para esto. |
| `GatewayNotice` | `kind: str`, `text: str`, `extra: Dict` | `Custom(name=kind, value={"text": text, **extra})` | `kind` ya es un string estable (`"restart"`, `"online"`, `"long_run"`, …) — se mapea directo al campo `name` de `Custom` sin necesidad de una tabla de traducción adicional. |

### Eventos que Hermes no modela explícitamente (los genera el bridge, no una traducción)

| AG-UI | Cuándo lo emite el bridge |
|---|---|
| `RunStarted(thread_id, run_id)` | Al aceptar un `RunAgentInput` y arrancar (o continuar) el turno correspondiente en la sesión de Hermes. |
| `RunFinished(thread_id, run_id)` | Al recibir `MessageStop(final=True)`, o cuando el turno termina con una tool call de frontend pendiente (ver `frontend-tools-flow.md`). |
| `RunError(thread_id, run_id, message)` | Si la sesión de Hermes lanza una excepción no recuperable durante el turno — Hermes no tiene hoy un evento de `stream_events.py` dedicado a esto; el bridge tendría que engancharse al manejo de errores de `run_agent.py`/`session.py`, algo no verificado en detalle. |

## Lo que falta confirmar

- Si `gateway/stream_events.py` cambia de forma (nuevos campos, nuevos tipos de evento) en versiones
  futuras de Hermes, esta tabla queda desactualizada — no hay garantía de estabilidad de esta interfaz
  interna documentada en ningún lado; es un módulo de implementación, no una API pública versionada.
- El estado de "plan/todos" (`_build_plan_update_from_todo_result` en `acp_adapter`) parsea el
  resultado de la tool `todo` desde un string JSON con un prefijo humano opcional. Reusar exactamente
  esa función para alimentar `StateDelta` en vez de `AgentPlanUpdate` es una idea razonable, pero no
  se ha probado que el resultado sea un JSON Patch (RFC 6902) válido sin trabajo adicional de diffing
  contra el snapshot anterior — `StateDelta` no es "el mismo dict", es una lista de operaciones patch.
