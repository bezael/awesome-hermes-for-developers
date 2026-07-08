# Next.js

Skills para que Hermes Agent trabaje sobre proyectos Next.js/React con criterio de arquitectura, no solo autocompletado.

## Skills recomendadas

### [`manish1803/nextjs-fullstack-skills`](https://github.com/manish1803/nextjs-fullstack-skills)
23 skills para Next.js, React, React Three Fiber, animaciones (GSAP/Framer Motion/Lottie), arquitectura MERN, pagos (Stripe/Razorpay) y sistemas de diseño UX/UI. Pensado para funcionar tanto con Hermes como con Google Antigravity, Claude Code y Cursor.

### [`stareezy-1/frontend-architecture-skill`](https://github.com/stareezy-1/frontend-architecture-skill)
6 skills agnósticas de framework para el ecosistema React/React Native: arquitectura, SEO, un gate de performance basado en Lighthouse, contratos de datos tipados, mutaciones optimistas y observabilidad.

## Nivel de madurez

| Skill | Stars | Última actualización | Licencia |
|---|---|---|---|
| nextjs-fullstack-skills | 0 | 2026-07-03 | MIT |
| frontend-architecture-skill | 10 | 2026-06-14 | MIT |

*0 stars no significa que no sirva — significa que casi nadie la ha probado todavía. Trátala con la misma cautela que cualquier dependencia nueva.*

## Casos de uso

- Generar componentes Next.js siguiendo un patrón de arquitectura consistente en vez de uno distinto por sesión
- Aplicar un gate de Lighthouse antes de dar por cerrada una tarea de performance
- Mantener contratos de datos tipados entre API routes y componentes cliente
- Integrar pagos (Stripe/Razorpay) sin reinventar el flujo en cada proyecto

## Instalación

Ambos repos son colecciones de múltiples skills, no un único `SKILL.md` en la raíz — revisa el README de cada uno para ubicar la carpeta de la skill puntual que quieras instalar. El patrón real de Hermes para instalar desde una URL directa:

```bash
hermes skills install https://raw.githubusercontent.com/<owner>/<repo>/main/<ruta-a-la-skill>/SKILL.md --force
```

`--force` es necesario porque son skills de la comunidad (trust level `community`), no oficiales. Si el SKILL.md no trae `name:` en el frontmatter, agrega `--name <alias>`.

## Vídeo demostración

*Pendiente de grabar.* Guion propuesto (2-3 min):
1. `hermes skills install ...` de una skill de `frontend-architecture-skill`
2. Pedirle a Hermes que audite un componente Next.js real contra esa skill
3. Mostrar el diff que propone y compararlo con el estado antes/después

## Ejemplo real

*Pendiente* — no hemos corrido estas skills contra un proyecto real todavía. Cuando se grabe el video de arriba, este apartado se actualiza con el output real (no uno inventado).
