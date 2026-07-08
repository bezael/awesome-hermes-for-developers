# Codex

Skills que conectan Hermes Agent con OpenAI Codex CLI — delegar tareas puntuales de código (y, en algunos casos, visión) desde Hermes hacia Codex y recuperar el resultado, sin necesariamente cambiar el runtime completo de la sesión.

## Skills recomendadas

### [`Rainhoole/hermes-agent-acp-skill`](https://github.com/Rainhoole/hermes-agent-acp-skill)
Skill de Hermes para delegación multi-agente estilo ACP. Desde el ángulo Codex: le da a Hermes un mecanismo para repartir una tarea de código hacia Codex (o Claude Code) usando un protocolo común, coordinar quién resuelve qué parte, y recuperar el resultado de vuelta a la sesión de Hermes. La misma skill aparece en la categoría [Claude Code](../Claude%20Code/README.md) — cubre ambos destinos de delegación, no es una casualidad de catalogación.

### [`ousiaresearch/hermes-theia-codex-vision`](https://github.com/ousiaresearch/hermes-theia-codex-vision)
Skill específica de Codex (no genérica): usa `codex exec` para tareas de visión que el `vision_analyze` nativo de Hermes no cubre — análisis detallado de imágenes y generación de imágenes con la herramienta `image_gen` de Codex (GPT-image), incluyendo generación con preservación de identidad a partir de una imagen de referencia. También documenta cómo registrar Codex como servidor MCP en Hermes para tareas de código. Nota importante de auth: Codex usa OAuth de ChatGPT Plus (`~/.codex/auth.json`), no `OPENAI_API_KEY`.

### [`codex-hermes-delegate`](skills/codex-hermes-delegate/SKILL.md) — original de Dominicode
Skill propia, escrita para este catálogo siguiendo el spec real de agentskills.io. Cubre el caso de delegar **una tarea de código puntual y acotada** a Codex CLI vía `codex exec`, verificar el resultado (lint/tests) antes de aceptarlo, e integrarlo a la memoria de Hermes — distinto del patrón "engine swap" (reemplazar todo el runtime de Hermes por Codex) y complementario a las otras dos skills de esta lista. **Es ilustrativa: no se ha corrido todavía contra un Hermes real.** Ver la sección "Verification" del propio `SKILL.md` para el checklist pendiente.

## Nivel de madurez

| Skill | Stars | Última actualización | Licencia |
|---|---|---|---|
| hermes-agent-acp-skill | 47 | 2026-03-07 | MIT |
| hermes-theia-codex-vision | 3 | 2026-05-24 | Sin licencia declarada |
| codex-hermes-delegate | — (original, no publicada) | 2026-07-08 | MIT |

*`hermes-theia-codex-vision` no declara licencia en el repo — antes de reusar su código (scripts, plantillas) en algo que no sea experimentación personal, confirma los términos con el autor. `codex-hermes-delegate` es una skill nueva de este catálogo: sus "stars" no existen todavía porque no vive en un repo público propio — vive aquí.*

## Casos de uso

- Que Hermes delegue una tarea de código puntual a Codex CLI y siga trabajando en paralelo en otra cosa (`codex-hermes-delegate`, `hermes-agent-acp-skill`)
- Generar o analizar imágenes usando el `image_gen` de Codex cuando el `vision_analyze` nativo de Hermes no alcanza (`hermes-theia-codex-vision`)
- Coordinar qué parte de una tarea resuelve Hermes, cuál Codex y cuál Claude Code bajo un mismo protocolo de delegación (`hermes-agent-acp-skill`)
- Registrar en la memoria de Hermes qué se delegó y qué se verificó, en vez de aplicar el resultado de un agente externo a ciegas (`codex-hermes-delegate`)

## Instalación

```bash
hermes skills install https://raw.githubusercontent.com/<owner>/<repo>/main/<ruta-a-la-skill>/SKILL.md --force
```

Para la skill original de este catálogo, instala directamente desde la ruta local o el raw de GitHub una vez el repo esté publicado:

```bash
hermes skills install ./Codex/skills/codex-hermes-delegate/SKILL.md --force
```

`hermes-agent-acp-skill` y `hermes-theia-codex-vision` son repos de una sola skill — revisa igual su README por si cambia la ruta interna del `SKILL.md`.

## Vídeo demostración

*Pendiente de grabar.* Guion propuesto (3-4 min):
1. Instalar `codex-hermes-delegate` en una instancia de Hermes real (con Codex CLI ya autenticado)
2. Pedirle a Hermes que delegue una tarea de código puntual (ej. "implementa esta función en `utils.py`") a Codex vía `codex exec`
3. Mostrar la verificación (lint/tests) antes de integrar el resultado
4. Mostrar la entrada que Hermes escribe en su memoria describiendo qué se delegó y qué se verificó

## Ejemplo real

*Pendiente* — no hemos corrido `codex-hermes-delegate` (ni las otras dos skills) contra una instancia real de Hermes todavía. Se actualiza con output real una vez grabado el video.
