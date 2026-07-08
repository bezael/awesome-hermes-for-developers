# Dimensionamiento de instancia para Hermes + sandbox Docker

## Qué carga realmente el host

Con `terminal.backend: docker`, la instancia sostiene simultáneamente:

- El proceso de Hermes en sí (Python 3.11 vía `uv` + Node.js v22 — dependencias que el propio instalador de Hermes maneja).
- El daemon Docker (`dockerd`) y su overhead de red/almacenamiento (overlay2, iptables, DNS embebido).
- Uno o más **contenedores de sandbox** por sesión activa — aquí es donde vive el costo real. Si el agente ejecuta `npm install`, corre una suite de tests, o levanta un servidor de desarrollo dentro del sandbox, ese contenedor consume CPU/RAM como cualquier proceso de build normal, no como un "script chiquito".
- Si el sandbox usa Playwright para tareas de navegador, los binarios de Chromium/Firefox/WebKit añaden cientos de MB de imagen y un consumo de RAM notable mientras un navegador headless está activo.

Nous Research no publica una cifra oficial de RAM/CPU mínima (confirmado contra la documentación pública en julio 2026). Lo de abajo es una recomendación de ingeniería, no una especificación del fabricante.

## Tabla de referencia (specs estables — no precios)

Las especificaciones de vCPU/RAM de una familia de instancia son estables y están documentadas por AWS; los *precios* no lo son. Verifica el precio siempre con `scripts/estimate-monthly-cost.sh`, nunca con esta tabla.

| Instancia | vCPU | RAM | Red | Burstable | Cuándo usarla |
|---|---|---|---|---|---|
| `t4g.small` | 2 | 2 GiB | Hasta 5 Gbps | Sí | Solo para probar la instalación de Hermes sin sandbox Docker activo. Insuficiente en cuanto el daemon Docker más un contenedor de sandbox estén corriendo a la vez. |
| `t4g.medium` | 2 | 4 GiB | Hasta 5 Gbps | Sí | Piso recomendado para uso real: una sesión de Hermes, tareas cortas dentro del sandbox. |
| `t4g.large` | 2 | 8 GiB | Hasta 5 Gbps | Sí | Una o dos sesiones, con builds/tests reales dentro del sandbox (el margen extra de RAM absorbe picos de `npm install`/compilación). |
| `t3.large` | 2 | 8 GiB | Hasta 5 Gbps | Sí | Equivalente x86 a `t4g.large` — solo si algo en el stack todavía no tiene soporte `aarch64` (poco común: Docker/Node/Python son multi-arch desde hace años, y la plataforma de Hermes declara `aarch64` como Tier 1). |
| `m7g.xlarge` | 4 | 16 GiB | Hasta 12.5 Gbps | No | Uso sostenido 24/7 con varias sesiones concurrentes o cargas de build pesadas y frecuentes. Sin techo de crédito de CPU — rendimiento predecible bajo carga continua. |

## Por qué Graviton (`t4g`/`m7g`) por defecto

La matriz de soporte de plataformas de Hermes declara Linux/Docker en `aarch64` como **Tier 1** (mismo nivel de prioridad que x86_64), y las imágenes base que Hermes instala (Node 22, Python 3.11) son multi-arquitectura oficiales. Eso significa que no hay razón técnica para pagar la prima de x86 (`t3`/`m7`) salvo que una dependencia específica del proyecto que corre dentro del sandbox no tenga build para ARM — verifícalo antes de descartar Graviton, no asumas incompatibilidad.

## Disco

- Usa `gp3`, no `gp2` (mismo IOPS/throughput base a menor costo por GB en los tamaños típicos de este caso de uso).
- Punto de partida: 30-40 GB. Eso cubre el sistema operativo, la instalación de Hermes, las imágenes Docker base, y margen para 2-3 imágenes de sandbox adicionales antes de necesitar limpieza.
- Automatiza `docker system prune -af --volumes` en un cron semanal (o antes de cada sesión larga) — sin esto, el disco se llena por acumulación de capas huérfanas, no por uso real creciente.
- Si el sandbox descarga datasets, repos grandes, o artefactos de build pesados de forma rutinaria, sube a 60-80 GB en vez de confiar en que la limpieza automática alcance a tiempo.
