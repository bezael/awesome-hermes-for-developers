# Docker

Skills para operar contenedores desde Hermes — más allá del sandbox de ejecución nativo que ya trae el propio agente (`terminal.backend: docker`).

## Skills recomendadas

### [`abdullahkhawer/devops-skills`](https://github.com/abdullahkhawer/devops-skills)
Colección curada de skills DevOps (incluye Docker) pensada para funcionar en Claude Code, GitHub Copilot, OpenCode, Mistral AI, Cursor y otros agentes compatibles con el estándar.

### [`stevenke1981/linux-agent-skills`](https://github.com/stevenke1981/linux-agent-skills)
63+ SKILL.md cubriendo Linux, Terminal, Docker, Kubernetes, seguridad y DevOps en general — más amplio que solo Docker, pero con varias skills puntuales relevantes.

## Nivel de madurez

| Skill | Stars | Última actualización | Licencia |
|---|---|---|---|
| devops-skills | 7 | 2026-05-07 | Apache-2.0 |
| linux-agent-skills | 0 | 2026-04-27 | Sin licencia declarada |

*`linux-agent-skills` no declara licencia en el repo — antes de usar su código en algo que no sea experimentación personal, confirma los términos con el autor.*

## Casos de uso

- Auditar un `docker-compose.yml` contra buenas prácticas antes de desplegar
- Automatizar tareas recurrentes de mantenimiento de contenedores (limpieza de imágenes huérfanas, rotación de logs)
- Complementar el sandbox nativo de Hermes con skills de diagnóstico cuando algo falla dentro del contenedor

## Instalación

```bash
hermes skills install https://raw.githubusercontent.com/<owner>/<repo>/main/<ruta-a-la-skill>/SKILL.md --force
```

Ambos son colecciones con varias skills — revisa el README de cada repo para encontrar la carpeta específica de la skill de Docker que te interesa antes de instalar.

## Vídeo demostración

*Pendiente de grabar.* Guion propuesto (2-3 min):
1. Activar el sandbox Docker nativo de Hermes (`hermes config set terminal.backend docker`)
2. Instalar una skill de auditoría de Docker de `devops-skills`
3. Pedirle a Hermes que revise un `docker-compose.yml` real y mostrar las recomendaciones

## Ejemplo real

*Pendiente* — no hemos corrido estas skills contra un proyecto real todavía. Se actualiza con output real una vez grabado el video.
