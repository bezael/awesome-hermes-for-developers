# Herramientas invocables desde la UI: el ciclo de dos runs

Confirmado contra `docs.ag-ui.com/concepts/tools` (julio 2026): AG-UI modela las "frontend tools"
como un protocolo **asíncrono, de dos ciclos de request/response** — no como una llamada bloqueante
donde el agente espera el resultado dentro del mismo turno. Esto es contraintuitivo si vienes de un
modelo mental de "function calling" síncrono, así que vale la pena documentarlo paso a paso antes de
tocar código.

## El ciclo completo

```
Frontend                              Bridge (agui_adapter)                Hermes
   |                                          |                               |
   | POST RunAgentInput                       |                               |
   |   thread_id, run_id                      |                               |
   |   tools: [{name, description, params}]   |                               |
   |------------------------------------------>                              |
   |                                          | registra tools del frontend  |
   |                                          | como toolset transitorio     |
   |                                          |------------------------------>|
   |                                          |                    modelo decide llamar
   |                                          |                    una tool del frontend
   |                                          |<------------------------------|
   |  SSE: RunStarted                        |                               |
   |<------------------------------------------                              |
   |  SSE: ToolCallStart(id, name)           |                               |
   |<------------------------------------------                              |
   |  SSE: ToolCallArgs(id, delta)           |                               |
   |<------------------------------------------                              |
   |  SSE: ToolCallEnd(id)                   |                               |
   |<------------------------------------------                              |
   |  SSE: RunFinished  <-- el run TERMINA aquí, con la tool call pendiente  |
   |<------------------------------------------                              |
   |                                          |                               |
   | (el frontend ejecuta la tool localmente) |                               |
   |                                          |                               |
   | POST RunAgentInput (nuevo)                |                              |
   |   mismo thread_id                        |                               |
   |   messages: [..., {role: "tool",         |                               |
   |     tool_call_id: id, content: result}]  |                               |
   |------------------------------------------>                              |
   |                                          | reconoce continuación,        |
   |                                          | inyecta el resultado como si  |
   |                                          | Hermes hubiera ejecutado la   |
   |                                          | tool él mismo                |
   |                                          |------------------------------>|
   |                                          |                    retoma generación
   |  SSE: RunStarted (nuevo run_id)          |                               |
   |<------------------------------------------                              |
   |  ... continúa normalmente ...            |                               |
```

## Qué le toca a cada lado

### Frontend (fuera del alcance de esta skill, pero relevante para el contrato)

- Declara la tool en `RunAgentInput.tools` con nombre, descripción y JSON Schema de parámetros —
  igual que declararías una function-calling tool para cualquier LLM.
- Acumula los deltas de `ToolCallArgs` hasta reconstruir el objeto de argumentos completo.
- Ejecuta la tool **localmente** (puede ser tan simple como leer un valor del estado de la UI, o tan
  complejo como abrir un modal y esperar input del usuario — AG-UI no le pone límite a esto).
- Abre un **nuevo** `RunAgentInput` con el mismo `thread_id`, agregando un mensaje `role: "tool"` que
  referencia el `tool_call_id` original.

### Bridge (`agui_adapter/`, lo que esta skill propone construir)

1. **Registrar el toolset transitorio.** Al recibir `RunAgentInput.tools`, exponer esos nombres/
   esquemas al modelo de Hermes para ese run específico — territorio de `toolsets.py`/
   `model_tools.py` en el repo de Hermes. Esta integración exacta (cómo inyectar un toolset
   *temporal*, scoped a un solo run, sin contaminar el toolset por defecto de la sesión) no está
   verificada línea por línea contra el código — es una hipótesis razonable sobre dónde engancharía,
   no una confirmación de que la API lo soporta tal cual hoy.
2. **Distinguir "tool local de Hermes" de "tool del frontend".** Cuando el modelo llama una tool que
   el bridge registró como proveniente del frontend, el bridge debe interceptarla *antes* de que
   Hermes intente ejecutarla localmente (no tiene implementación local — ejecutarla fallaría o, peor,
   sería un no-op silencioso). En su lugar, emite `ToolCallStart`/`Args`/`End` y cierra el run.
3. **Cerrar el run con la tool call pendiente, no como un error.** `RunFinished` aquí no significa
   "la conversación terminó" — significa "este ciclo HTTP/SSE terminó, el turno lógico sigue abierto
   y se reanudará en un próximo `RunAgentInput` con el mismo `thread_id`". Esto es exactamente lo que
   más se aleja del modelo mental de "un turno de Hermes = una ejecución continua" y por eso es el
   punto marcado como mayor riesgo en el `SKILL.md` principal.
4. **Reconocer la continuación.** Al recibir un `RunAgentInput` posterior cuyo último mensaje es
   `role: "tool"` con un `tool_call_id` que el bridge recuerda haber emitido, debe inyectar ese
   contenido en la sesión de Hermes como si fuera el resultado normal de una tool call — no como un
   mensaje de usuario nuevo. Cómo hacer esto sin romper el historial de conversación que Hermes
   persiste internamente es, otra vez, algo que debe verificarse contra el código real de
   `session.py`/`session_context.py`, no algo que este documento pueda garantizar.

### Hermes (sin cambios asumidos, salvo que el punto 4 lo requiera)

- Idealmente, Hermes no necesita saber que el resultado de una tool vino de un frontend AG-UI en vez
  de su propio subproceso de ejecución — desde su perspectiva, una tool call salió y un resultado
  volvió. Si el mecanismo de sesión de Hermes no permite inyectar un resultado de tool "desde afuera"
  de esa forma, este punto se convierte en un cambio necesario en Hermes, no solo en el adapter — y
  eso cambiaría el alcance de esta skill de "bridge externo" a "parche + bridge".

## Por qué este diseño (y no un bloqueo síncrono)

Una alternativa más simple de imaginar sería: el bridge recibe `ToolCallChunk`, abre una promesa,
bloquea el hilo de Hermes hasta que el frontend responda por otro canal (WebSocket, polling), y
resuelve la promesa con el resultado antes de que Hermes continúe generando. **Esto no es cómo AG-UI
está diseñado** (confirmado: "tool execution is non-blocking from the agent's perspective... the
protocol assumes the frontend will handle execution and return results through a continuation
mechanism, rather than the agent waiting synchronously") y tratar de forzarlo así iría contra el
protocolo — además de requerir que `run_agent.py` soporte pausar un hilo de ejecución indefinidamente,
lo cual es una superficie de riesgo mayor (timeouts, fugas de hilos, sesiones colgadas) que el modelo
de dos ciclos que el protocolo ya resuelve.
