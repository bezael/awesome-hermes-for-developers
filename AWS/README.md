# AWS

A diferencia de Next.js, Docker o Claude Code, el ecosistema de skills *específicas* de AWS para agentes tipo Hermes está débil. Lo que existe en su mayoría es genérico (FinOps multi-nube que trata a AWS como una de tres nubes intercambiables) o tangencial (bridges de cómputo GPU donde AWS aparece solo como una opción de egress de artefactos). La estrategia de esta categoría es distinta a la del resto del catálogo: **curar donde exista algo genuinamente específico, crear donde no**. Aquí el balance se inclina hacia crear.

## Skills recomendadas (curación)

### [`toddkasper/expert-skills`](https://github.com/toddkasper/expert-skills) — carpeta `aws/skills/`
Tres playbooks operativos escalonados por el temario de certificaciones AWS Professional/Specialty (no es contenido de "preparación de examen" — la certificación se usa como andamiaje y benchmark de cobertura, el producto es la competencia operativa real):
- `aws-solutions-architect-professional` — arquitectura multi-cuenta, redes híbridas (Transit Gateway, PrivateLink, Direct Connect), estrategia de migración (los 7 Rs).
- `aws-devops-engineer-professional` — pipelines CI/CD (CodePipeline/CodeBuild/CodeDeploy), IaC, estrategias de despliegue blue/green y canary, observabilidad.
- `aws-security-specialty` — detección de amenazas (GuardDuty, Security Hub), IAM, seguridad de red (security groups, NACLs, WAF), KMS.

Cada archivo etiqueta explícitamente qué es un hecho estable y qué es `[volatile — verify live]` (precios, límites de servicio) — una disciplina que vale la pena imitar.

### [`haideralimazari/aws-skills`](https://github.com/haideralimazari/aws-skills) — skill `aws-core`
Guía de buenas prácticas para EC2, S3, Lambda, ECS, IAM y CloudFormation, dividida en archivos de referencia por servicio. Cubre selección de tipo de instancia, security groups y optimización de costo (Spot, Reserved, Graviton) con suficiente especificidad como para ser accionable, no solo un resumen de la documentación oficial.

*Advertencia:* el README de este repo muestra un badge "License: MIT", pero el repositorio **no tiene un archivo `LICENSE`** (verificado vía API de GitHub) — antes de reutilizar su código más allá de leerlo como referencia, confirma los términos directamente con el autor.

Ninguno de los dos está empaquetado para instalarse con un solo comando de Hermes apuntando a la raíz del repo — son colecciones, revisa la ruta exacta de cada skill antes de instalar.

## Original — creada por Dominicode

### [`aws-vps-cost-check`](./skills/aws-vps-cost-check/)
No encontramos nada en el ecosistema real que cubriera el caso de uso más común para alguien de esta comunidad: revisar una instancia EC2/Lightsail *antes* de desplegar Hermes con el sandbox Docker activo. Así que la escribimos nosotros.

Qué hace: dado un tipo de instancia y una región, (1) recomienda una familia de instancia según el perfil de carga (sesiones concurrentes, si el sandbox corre builds/tests pesados), (2) calcula el costo mensual real consultando la AWS Pricing API en vivo — nunca una tabla de precios memorizada — y (3) audita el security group contra tres errores concretos: SSH abierto a `0.0.0.0/0`, el puerto del daemon Docker expuesto a la red, y rangos de puertos abiertos sin propósito declarado.

Incluye un script (`scripts/estimate-monthly-cost.sh`) que de verdad ejecuta la consulta a AWS Pricing API vía CLI + `jq`, una guía de dimensionamiento (`references/instance-sizing.md`) razonada a partir de qué carga real impone Hermes al host (no una tabla inventada), un checklist de security groups (`references/security-group-checklist.md`), y una plantilla Terraform de referencia (`templates/security-group.tf`).

## Nivel de madurez

| Skill | Stars | Última actualización | Licencia |
|---|---|---|---|
| expert-skills | 1 | 2026-06-11 | MIT |
| aws-skills (aws-core) | 0 | 2026-05-06 | Sin archivo LICENSE (README dice MIT) |
| aws-vps-cost-check | — (nueva, propia de Dominicode) | 2026-07-08 | MIT |

*1 star en `expert-skills` no es tracción real todavía — la calidad del contenido (etiquetado de volatilidad, alcance acotado por skill) es lo que la hace recomendable, no las stars.*

## Casos de uso

- Decidir si una instancia EC2/Lightsail ya existente le alcanza al sandbox Docker de Hermes antes de que falle a mitad de una sesión larga
- Obtener un costo mensual real (Pricing API en vivo) en vez de una cifra de memoria que puede estar desactualizada
- Auditar security groups antes de exponer el host a internet — específicamente, evitar el error de dejar el daemon Docker alcanzable desde la red
- Diseñar arquitecturas AWS complejas (multi-cuenta, migración, DR) con el nivel de profundidad de un Solutions Architect Professional
- Construir pipelines CI/CD y estrategias de despliegue (blue/green, canary) siguiendo el temario de DevOps Engineer Professional
- Revisar detección de amenazas e IAM con el criterio de Security Specialty

## Instalación

```bash
# Skills curadas de terceros (community trust — usa --force)
hermes skills install https://raw.githubusercontent.com/<owner>/<repo>/main/<ruta-a-la-skill>/SKILL.md --force

# La skill original de este catálogo, una vez esté en tu propio fork/checkout:
hermes skills install https://raw.githubusercontent.com/bezael/awesome-hermes-for-developers/main/AWS/skills/aws-vps-cost-check/SKILL.md --force
```

`expert-skills` y `aws-skills` son colecciones con varias skills — ubica la ruta exacta de la que te interesa en su README antes de instalar. `aws-vps-cost-check` sí es un único `SKILL.md` en la ruta de arriba.

## Vídeo demostración

*Pendiente de grabar.* Guion propuesto (3-4 min):
1. Lanzar una instancia `t4g.medium` de prueba en una cuenta AWS real (sandbox, no producción)
2. Instalar `aws-vps-cost-check` en una instancia de Hermes real y pedirle que revise el security group por defecto
3. Mostrar el hallazgo (SSH abierto a `0.0.0.0/0` en un security group recién creado es el caso típico) y el costo mensual real que devuelve el script contra la Pricing API
4. Corregir el security group con `templates/security-group.tf` y volver a correr la verificación

## Ejemplo real

*Pendiente* — no hemos corrido `aws-vps-cost-check` contra un Hermes real todavía. Lo de abajo es un ejemplo **ilustrativo de la interacción esperada**, no una captura de terminal real — no lo tomes como output verificado:

> **Operador:** "Voy a desplegar Hermes en esta instancia `t3.micro` que ya tengo corriendo, ¿le alcanza?"
> **Hermes (con la skill activa, respuesta esperada):** señalaría que `t3.micro` (1 GiB RAM) está por debajo del piso recomendado para sostener el daemon Docker más un contenedor de sandbox a la vez, sugeriría subir a `t4g.medium` como mínimo, y ofrecería correr `scripts/estimate-monthly-cost.sh t4g.medium us-east-1 40` para dar el costo real antes de que el operador decida.

Este apartado se actualiza con el output real la primera vez que alguien la corra de verdad — no antes.
