# Claude Code

Skills que conectan Hermes Agent con Claude Code — no son skills "sobre" Claude Code, sino puentes reales entre ambos para delegar trabajo de un lado a otro.

## Skills recomendadas

### [`Rainhoole/hermes-agent-acp-skill`](https://github.com/Rainhoole/hermes-agent-acp-skill)
Skill de Hermes para delegación multi-agente estilo ACP entre Hermes, Codex y Claude Code — le permite a Hermes repartir tareas hacia estas otras herramientas y recuperar el resultado.

### [`lingjiuu/hermes-dynamic-workflows`](https://github.com/lingjiuu/hermes-dynamic-workflows)
Scripts de workflow dinámicos para Hermes, con un estilo de definición similar al que usa Claude Code.

### [`42-evey/evey-bridge-plugin`](https://github.com/42-evey/evey-bridge-plugin)
Plugin de Claude Code que hace de puente con Hermes: auto-chequeo de mensajes y un loop de supervisión ("Mother Mode").

## Nivel de madurez

| Skill | Stars | Última actualización | Licencia |
|---|---|---|---|
| hermes-agent-acp-skill | 47 | 2026-03-07 | MIT |
| hermes-dynamic-workflows | 92 | 2026-06-09 | MIT |
| evey-bridge-plugin | 11 | 2026-06-18 | MIT |

*Son las de mayor tracción de todo el piloto (47-92 stars) — pero "más stars" no es lo mismo que "auditado por nosotros". Sigue aplicando el mismo criterio de revisión.*

## Casos de uso

- Que Hermes delegue una tarea de código puntual a Claude Code y siga trabajando en paralelo en otra cosa
- Definir workflows reutilizables en Hermes con una sintaxis que ya conoces si usas Claude Code
- Supervisar desde Claude Code lo que Hermes está haciendo en background, sin tener que entrar al servidor

## Instalación

```bash
hermes skills install https://raw.githubusercontent.com/<owner>/<repo>/main/<ruta-a-la-skill>/SKILL.md --force
```

`evey-bridge-plugin` se instala del lado de Claude Code (no de Hermes) — revisa su README para el mecanismo de instalación de plugins de Claude Code.

## Vídeo demostración

*Pendiente de grabar.* Guion propuesto (3-4 min):
1. Instalar `hermes-agent-acp-skill` en una instancia de Hermes real
2. Pedirle a Hermes una tarea que delegue explícitamente a Claude Code
3. Mostrar el resultado devuelto y cómo Hermes lo integra a su memoria

## Ejemplo real

*Pendiente* — no hemos corrido esta delegación de verdad todavía. Se actualiza con el output real una vez grabado el video.
