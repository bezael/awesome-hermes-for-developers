#!/usr/bin/env python3
"""Valida invariantes estructurales de un log de eventos AG-UI (JSONL).

Este script SI es real y ejecutable -- a diferencia del resto de esta skill
(que es una propuesta de arquitectura sin ejecutar), esto es una utilidad de
verificacion pura sobre el formato de eventos de AG-UI, sin dependencias de
Hermes ni del SDK de AG-UI. Solo requiere la libreria estandar de Python.

Uso:
    python check_event_sequence.py eventos.jsonl

Formato esperado del archivo: una linea por evento, cada linea un objeto JSON
con al menos un campo "type" (ej. "RUN_STARTED", "TEXT_MESSAGE_START", ...).
Los nombres de tipo aceptados son insensibles a mayusculas/guion bajo vs
CamelCase, para tolerar tanto el estilo "RUN_STARTED" (wire format tipico de
AG-UI) como "RunStarted" (nombre de clase en el SDK de Python/TS).

Invariantes que valida:
  1. El log empieza con RUN_STARTED y termina con RUN_FINISHED o RUN_ERROR.
  2. Cada TEXT_MESSAGE_START tiene un TEXT_MESSAGE_END con el mismo message_id,
     y no hay TEXT_MESSAGE_CONTENT/END sin un START previo para ese id.
  3. Cada TOOL_CALL_START tiene un TOOL_CALL_END con el mismo tool_call_id, y
     no hay TOOL_CALL_ARGS/END sin un START previo para ese id.
  4. No quedan mensajes ni tool calls abiertos al terminar el log (salvo que
     el log termine en RUN_ERROR, donde un cierre abrupto es esperable).

Esto NO valida semantica de negocio (si el contenido tiene sentido) ni que el
log venga de un Hermes real -- solo la forma del protocolo.
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass, field


def _normalize_type(raw_type: str) -> str:
    """Normaliza "RunStarted" y "RUN_STARTED" a la misma clave interna."""
    if "_" in raw_type:
        # Ya viene en estilo SCREAMING_SNAKE_CASE (el wire format tipico de AG-UI).
        return raw_type.upper()
    # CamelCase (nombre de clase del SDK) -> SCREAMING_SNAKE_CASE.
    snake = re.sub(r"(?<!^)(?=[A-Z])", "_", raw_type)
    return snake.upper()


@dataclass
class ValidationResult:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors


def check_event_sequence(events: list[dict]) -> ValidationResult:
    result = ValidationResult()

    if not events:
        result.errors.append("El log esta vacio -- no hay eventos que validar.")
        return result

    first_type = _normalize_type(events[0].get("type", ""))
    if first_type != "RUN_STARTED":
        result.errors.append(
            f"El primer evento deberia ser RUN_STARTED, no '{events[0].get('type')}'."
        )

    last_type = _normalize_type(events[-1].get("type", ""))
    if last_type not in ("RUN_FINISHED", "RUN_ERROR"):
        result.errors.append(
            f"El ultimo evento deberia ser RUN_FINISHED o RUN_ERROR, no '{events[-1].get('type')}'."
        )

    open_messages: dict[str, int] = {}
    open_tool_calls: dict[str, int] = {}

    for i, event in enumerate(events):
        etype = _normalize_type(event.get("type", ""))

        if etype == "TEXT_MESSAGE_START":
            msg_id = event.get("message_id")
            if msg_id is None:
                result.errors.append(f"[evento {i}] TEXT_MESSAGE_START sin message_id.")
                continue
            if msg_id in open_messages:
                result.errors.append(
                    f"[evento {i}] TEXT_MESSAGE_START duplicado para message_id={msg_id} "
                    f"(ya abierto en el evento {open_messages[msg_id]})."
                )
            open_messages[msg_id] = i

        elif etype == "TEXT_MESSAGE_CONTENT":
            msg_id = event.get("message_id")
            if msg_id not in open_messages:
                result.errors.append(
                    f"[evento {i}] TEXT_MESSAGE_CONTENT para message_id={msg_id} sin un "
                    "TEXT_MESSAGE_START previo."
                )

        elif etype == "TEXT_MESSAGE_END":
            msg_id = event.get("message_id")
            if msg_id not in open_messages:
                result.errors.append(
                    f"[evento {i}] TEXT_MESSAGE_END para message_id={msg_id} sin un "
                    "TEXT_MESSAGE_START previo."
                )
            else:
                del open_messages[msg_id]

        elif etype == "TOOL_CALL_START":
            tool_id = event.get("tool_call_id")
            if tool_id is None:
                result.errors.append(f"[evento {i}] TOOL_CALL_START sin tool_call_id.")
                continue
            if tool_id in open_tool_calls:
                result.errors.append(
                    f"[evento {i}] TOOL_CALL_START duplicado para tool_call_id={tool_id} "
                    f"(ya abierto en el evento {open_tool_calls[tool_id]})."
                )
            open_tool_calls[tool_id] = i

        elif etype == "TOOL_CALL_ARGS":
            tool_id = event.get("tool_call_id")
            if tool_id not in open_tool_calls:
                result.errors.append(
                    f"[evento {i}] TOOL_CALL_ARGS para tool_call_id={tool_id} sin un "
                    "TOOL_CALL_START previo."
                )

        elif etype == "TOOL_CALL_END":
            tool_id = event.get("tool_call_id")
            if tool_id not in open_tool_calls:
                result.errors.append(
                    f"[evento {i}] TOOL_CALL_END para tool_call_id={tool_id} sin un "
                    "TOOL_CALL_START previo."
                )
            else:
                del open_tool_calls[tool_id]

        elif etype == "RUN_ERROR" and i != len(events) - 1:
            result.warnings.append(
                f"[evento {i}] RUN_ERROR no es el ultimo evento del log -- "
                "revisa si hay eventos huerfanos despues de un error."
            )

    if last_type == "RUN_FINISHED":
        for msg_id, idx in open_messages.items():
            result.errors.append(
                f"message_id={msg_id} (abierto en el evento {idx}) nunca se cerro con "
                "TEXT_MESSAGE_END antes de RUN_FINISHED."
            )
        for tool_id, idx in open_tool_calls.items():
            result.errors.append(
                f"tool_call_id={tool_id} (abierto en el evento {idx}) nunca se cerro con "
                "TOOL_CALL_END antes de RUN_FINISHED."
            )
    elif open_messages or open_tool_calls:
        result.warnings.append(
            "El log termino en RUN_ERROR con mensajes/tool calls abiertos -- "
            "esperable en un cierre abrupto, pero confirma que es intencional."
        )

    return result


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"Uso: {argv[0]} <archivo.jsonl>", file=sys.stderr)
        return 2

    path = argv[1]
    events = []
    with open(path, "r", encoding="utf-8") as f:
        for line_no, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError as exc:
                print(f"Linea {line_no} no es JSON valido: {exc}", file=sys.stderr)
                return 2

    result = check_event_sequence(events)

    for warning in result.warnings:
        print(f"AVISO: {warning}")
    for error in result.errors:
        print(f"ERROR: {error}")

    if result.ok:
        print(f"OK -- {len(events)} eventos, secuencia estructuralmente valida.")
        return 0

    print(f"FALLO -- {len(result.errors)} error(es) encontrados en {len(events)} eventos.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
