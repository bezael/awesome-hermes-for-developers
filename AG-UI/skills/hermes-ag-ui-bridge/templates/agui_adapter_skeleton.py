"""Esqueleto ILUSTRATIVO de un bridge Hermes -> AG-UI.

Estado: propuesta de diseño, NO ejecutado contra un Hermes real ni contra un
cliente AG-UI real. No copies esto a producción tal cual — es un punto de
partida para razonar la forma del código, con los huecos marcados
explícitamente como TODO/VERIFICAR en vez de rellenados con una suposición.

Dependencias asumidas (no instaladas ni probadas en este repo):
  - `ag_ui.core`    (tipos de evento: RunStartedEvent, TextMessageContentEvent, ...)
  - `ag_ui.encoder` (EventEncoder, para serializar según el header Accept)
  - un framework ASGI cualquiera (FastAPI, Starlette...) para el endpoint SSE

Ver references/event-mapping.md para la tabla completa de traducción y
references/frontend-tools-flow.md para el ciclo de tools de frontend.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, AsyncIterator, Optional

# --- Tipos que representan lo que gateway/stream_events.py de Hermes ya define.
# Reproducidos aquí solo por forma (nombre de campos), no importados: esta skill
# no asume acceso al paquete interno de Hermes como dependencia instalable.


@dataclass(frozen=True)
class MessageChunk:
    text: str


@dataclass(frozen=True)
class MessageStop:
    final: bool = False


@dataclass(frozen=True)
class Commentary:
    text: str


@dataclass(frozen=True)
class ToolCallChunk:
    tool_name: str
    preview: Optional[str] = None
    args: Optional[dict] = None
    index: int = 0


@dataclass(frozen=True)
class ToolCallFinished:
    tool_name: str
    duration: float = 0.0
    ok: bool = True
    index: int = 0


# --- Traductor: Hermes StreamEvent -> eventos AG-UI (como dicts genéricos aquí;
# en una implementación real serían instancias de ag_ui.core.*Event).


class AGUIEventTranslator:
    """Traduce el vocabulario de streaming de Hermes al vocabulario de AG-UI.

    Mantiene el estado mínimo necesario para saber si ya abrió un mensaje de
    texto (para no emitir TextMessageContent sin un TextMessageStart previo) y
    para asignar message_id a los ciclos de Commentary.
    """

    def __init__(self, thread_id: str, run_id: str) -> None:
        self.thread_id = thread_id
        self.run_id = run_id
        self._current_message_id: Optional[str] = None
        self._message_counter = 0

    def _new_message_id(self) -> str:
        self._message_counter += 1
        return f"{self.run_id}-msg-{self._message_counter}"

    def translate(self, event: Any) -> list[dict]:
        """Devuelve una lista de eventos AG-UI (dicts) para un evento de Hermes.

        Una lista porque algunos eventos de Hermes se expanden a más de un
        evento AG-UI (ej. MessageStop(final=True) -> TextMessageEnd + RunFinished).
        """
        if isinstance(event, MessageChunk):
            out = []
            if self._current_message_id is None:
                self._current_message_id = self._new_message_id()
                out.append({"type": "TEXT_MESSAGE_START", "message_id": self._current_message_id})
            out.append(
                {
                    "type": "TEXT_MESSAGE_CONTENT",
                    "message_id": self._current_message_id,
                    "delta": event.text,
                }
            )
            return out

        if isinstance(event, MessageStop):
            out = []
            if self._current_message_id is not None:
                out.append({"type": "TEXT_MESSAGE_END", "message_id": self._current_message_id})
                self._current_message_id = None
            if event.final:
                out.append({"type": "RUN_FINISHED", "thread_id": self.thread_id, "run_id": self.run_id})
            return out

        if isinstance(event, Commentary):
            msg_id = self._new_message_id()
            return [
                {"type": "TEXT_MESSAGE_START", "message_id": msg_id},
                {"type": "TEXT_MESSAGE_CONTENT", "message_id": msg_id, "delta": event.text},
                {"type": "TEXT_MESSAGE_END", "message_id": msg_id},
            ]

        if isinstance(event, ToolCallChunk):
            tool_call_id = str(event.index)
            out = [
                {
                    "type": "TOOL_CALL_START",
                    "tool_call_id": tool_call_id,
                    "tool_call_name": event.tool_name,
                }
            ]
            if event.args is not None:
                out.append(
                    {
                        "type": "TOOL_CALL_ARGS",
                        "tool_call_id": tool_call_id,
                        "delta": json.dumps(event.args),
                    }
                )
            return out

        if isinstance(event, ToolCallFinished):
            # NOTA: no hay output de la tool disponible aquí -- ver
            # references/event-mapping.md. ToolCallResult, si se necesita,
            # tendría que construirse leyendo el historial de mensajes de
            # Hermes por otra vía, no a partir de este evento.
            return [{"type": "TOOL_CALL_END", "tool_call_id": str(event.index)}]

        # LongToolHint / GatewayNotice / cualquier otro -> Custom genérico.
        kind = getattr(event, "kind", type(event).__name__)
        return [{"type": "CUSTOM", "name": kind, "value": vars(event)}]


# --- Endpoint SSE ilustrativo (pseudocódigo de forma ASGI-agnóstica).
#
# TODO / SIN VERIFICAR: cómo arrancar/continuar exactamente una sesión de
# Hermes (session_context.py) a partir de thread_id/run_id, y cómo suscribirse
# al StreamEvent real que emite el agente en ejecución -- esto depende del
# entrypoint real de run_agent.py, que esta skill no ha inspeccionado línea a
# línea. Lo de abajo asume una función `run_hermes_turn(...)` que no existe
# todavía con esta firma.


async def handle_run_agent_input(run_agent_input: dict) -> AsyncIterator[bytes]:
    """Firma ilustrativa de lo que sería el handler del endpoint POST /run.

    En una implementación real esto usaría `ag_ui.encoder.EventEncoder` para
    serializar cada evento según el header Accept del cliente, en vez de un
    json.dumps manual como aquí.
    """
    thread_id = run_agent_input["thread_id"]
    run_id = run_agent_input["run_id"]
    translator = AGUIEventTranslator(thread_id=thread_id, run_id=run_id)

    yield _sse(("RUN_STARTED", {"thread_id": thread_id, "run_id": run_id}))

    # TODO: reemplazar por la suscripción real al StreamEvent de Hermes.
    # async for hermes_event in run_hermes_turn(run_agent_input):
    #     for agui_event in translator.translate(hermes_event):
    #         yield _sse(agui_event)
    raise NotImplementedError(
        "Esqueleto ilustrativo -- conectar con el loop real de Hermes "
        "(run_agent.py / session_context.py) queda pendiente de verificación."
    )


def _sse(event: Any) -> bytes:
    if isinstance(event, tuple):
        event_type, payload = event
        payload = {"type": event_type, **payload}
    else:
        payload = event
    return f"data: {json.dumps(payload)}\n\n".encode("utf-8")
