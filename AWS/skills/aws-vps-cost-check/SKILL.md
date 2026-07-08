---
name: aws-vps-cost-check
description: Revisa la configuración de una instancia EC2 o Lightsail antes de desplegar Hermes Agent con el sandbox Docker — tipo de instancia adecuado para correr el daemon Docker más contenedores de sandbox, reglas de grupos de seguridad (security groups) y costo mensual estimado usando la AWS Pricing API real. Úsala cuando el usuario vaya a desplegar Hermes en AWS y pregunte cosas como "qué instancia EC2 necesito para Hermes", "esta instancia le va a alcanzar al sandbox Docker", "revisa mis security groups antes de desplegar" o "cuánto me va a costar esto al mes".
version: "1.0.0"
license: MIT
compatibility: Requiere AWS CLI v2 autenticado (aws sts get-caller-identity funcionando), jq, y permisos IAM ec2:Describe* + pricing:GetProducts en la cuenta objetivo.
metadata:
  author: dominicode
  hermes:
    tags: [aws, ec2, lightsail, docker, sandbox, cost, security-groups, deployment]
    category: infra-cost
---

# AWS VPS Cost Check

Skill de preflight para desplegar Hermes Agent en una instancia EC2 o Lightsail usando el backend `terminal.backend: docker` (sandbox de ejecución en contenedores). No reemplaza el juicio del operador — le da a Hermes (o a quien lo esté configurando) una checklist concreta y un número real de costo antes de aprobar el despliegue.

**Nota de honestidad:** Nous Research no publica requisitos mínimos oficiales de hardware para Hermes Agent (verificado en la documentación pública de `hermes-agent.nousresearch.com` en julio 2026 — solo se menciona que corre desde "un VPS de $5" hasta un clúster GPU, sin desglose de RAM/CPU). Las recomendaciones de esta skill son ingeniería de sentido común basada en la carga de trabajo real que Hermes impone al host: proceso Python 3.11 + Node.js v22 residentes, el daemon Docker en sí, y contenedores de sandbox efímeros que instalan dependencias y corren builds/tests dentro. Trátalas como punto de partida, no como cifra oficial de Nous Research.

## When to Use

- Antes de lanzar (`aws ec2 run-instances`) o redimensionar la instancia donde correrá Hermes con sandbox Docker.
- Cuando el operador ya tiene una instancia corriendo y quiere una segunda opinión sobre si el tipo de instancia, el disco y los security groups son razonables antes de exponerla a internet.
- Cuando alguien pregunta "¿cuánto me va a costar esto al mes?" y quiere un número real, no una tabla de precios de memoria (que se desactualiza).
- No la uses para dimensionar clústers multi-nodo, EKS, o cargas de entrenamiento/inferencia de modelos — es específica para el patrón "una instancia, un Hermes, sandbox Docker local".

## Procedure

### 1. Perfila la carga de trabajo antes de elegir instancia

Pregunta (o infiere del contexto) cuántas sesiones de Hermes van a correr concurrentemente y qué tan pesado es lo que el agente ejecuta dentro del sandbox (¿solo scripts cortos? ¿`npm install` + build + test suite completo?). Eso determina la fila correcta en `references/instance-sizing.md`. Regla rápida:

| Perfil | vCPU/RAM mínimo recomendado | Familia sugerida |
|---|---|---|
| 1 sesión, tareas cortas, uso personal/pruebas | 2 vCPU / 4 GiB | `t4g.medium` |
| 1-2 sesiones, builds/tests dentro del sandbox | 2 vCPU / 8 GiB | `t4g.large` / `t3.large` |
| Varias sesiones concurrentes o uso 24/7 sostenido | 4 vCPU / 16 GiB, sin CPU burstable | `m7g.xlarge` |

Ver `references/instance-sizing.md` para el razonamiento completo (por qué burstable es riesgoso en uso sostenido, por qué Graviton/`t4g` es la opción por defecto).

### 2. Corre el estimado de costo real (no de memoria)

No cites precios de memoria — cambian. Usa el script incluido, que consulta la AWS Pricing API en vivo:

```bash
scripts/estimate-monthly-cost.sh t4g.medium us-east-1 40
```

Esto imprime cómputo (on-demand, 730h/mes) + almacenamiento EBS gp3 estimado. Reporta el número al operador con la fecha de la consulta — es una cotización del momento, no una tarifa fija.

### 3. Revisa (o genera) los security groups antes de exponer el puerto

Sigue la checklist en `references/security-group-checklist.md`. Los tres errores que esta skill existe para prevenir:

1. SSH (22) abierto a `0.0.0.0/0` en vez de a la IP/CIDR del operador.
2. El puerto del daemon Docker (2375/2376) expuesto a cualquier CIDR — un daemon Docker remoto sin TLS mutuo equivale a root shell para quien lo alcance.
3. Abrir un rango de puertos "por si acaso" en vez del puerto exacto que Hermes necesita (SSH de administración + el puerto de la UI/API de Hermes si aplica, restringido a IPs conocidas).

Usa `templates/security-group.tf` como punto de partida (Terraform) si el operador va a crear el grupo desde cero, o compáralo contra el grupo existente con `aws ec2 describe-security-groups`.

### 4. Reporta un resumen accionable

Entrega siempre estos tres datos juntos, no por separado: tipo de instancia recomendado + costo mensual estimado (cómputo + EBS) + lista de hallazgos de security group (o "sin hallazgos" si ya está bien). Si falta información (el operador no dijo cuántas sesiones concurrentes espera, o no compartió el ID del security group), pregunta antes de asumir — un sobre-dimensionamiento cuesta dinero real cada mes, y un sub-dimensionamiento causa fallos intermitentes en el sandbox que son difíciles de diagnosticar después.

## Pitfalls

- **Instancias burstable (`t3`/`t4g`) bajo carga sostenida:** acumulan créditos de CPU con un tope; una sesión larga de Hermes ejecutando builds repetidos dentro del sandbox puede agotarlos y entrar en *throttling* silencioso — el síntoma es que el agente "se pone lento" sin error explícito. Si el uso va a ser 24/7 con carga real, no burstable, o activa el modo `unlimited` de CloudWatch/EC2 para esa instancia (tiene costo adicional cuando se excede el crédito base).
- **El "VPS de $5" que menciona la propia documentación de Hermes no aplica al backend Docker:** ese ejemplo asume backends `local` o `ssh` (sin daemon Docker ni contenedores de sandbox). Con `terminal.backend: docker`, el daemon en sí más las imágenes base (Node 22, Python 3.11, y si el sandbox usa Playwright, los binarios de Chromium/Firefox/WebKit pesan varios cientos de MB extra cada uno) ya empujan el uso de RAM y disco por encima de lo que un plan de 512MB-1GB puede sostener de forma confiable.
- **Disco quedándose sin espacio por acumulación de imágenes Docker:** cada sesión de sandbox puede dejar capas de imagen huérfanas. Sin un `docker system prune` periódico (cron semanal es razonable), un volumen de 20GB se llena en semanas, no meses. Dimensiona con margen (ver `references/instance-sizing.md`) y automatiza la limpieza, no confíes en limpiar manualmente.
- **gp2 en vez de gp3:** gp2 cuesta más por GB que gp3 para un IOPS/throughput equivalente en la mayoría de los tamaños de disco típicos de este caso de uso — no hay razón para usar gp2 en un despliegue nuevo.
- **Citar un precio de EC2 de memoria como si fuera actual:** los precios on-demand cambian por región y con el tiempo. Esta skill fuerza a consultar la Pricing API en vivo (`scripts/estimate-monthly-cost.sh`) precisamente para evitar este error — si el script falla (sin credenciales, sin permisos `pricing:GetProducts`), dilo explícitamente en vez de rellenar con un número de memoria.
- **IAM instance profile de más:** si la instancia necesita leer una API key desde Secrets Manager o SSM Parameter Store, dale un rol con permiso *solo* a ese secreto específico (`secretsmanager:GetSecretValue` con `Resource` acotado al ARN exacto), no `SecretsManagerReadWrite` ni permisos administrativos "para que funcione".

## Verification

Después de aplicar cambios (nueva instancia, nuevo security group, o resize), verifica con comandos reales, no de memoria:

```bash
# La instancia existe, el tipo es el esperado, y el estado es running
aws ec2 describe-instances --instance-ids <id> \
  --query 'Reservations[0].Instances[0].{Type:InstanceType,State:State.Name,AZ:Placement.AvailabilityZone}'

# El security group no tiene SSH abierto al mundo
aws ec2 describe-security-groups --group-ids <sg-id> \
  --query 'SecurityGroups[0].IpPermissions[?ToPort==`22`].IpRanges[].CidrIp'
# Cualquier resultado distinto de la IP/CIDR del operador es un hallazgo a reportar.

# Ningún puerto del daemon Docker (2375/2376) expuesto externamente
aws ec2 describe-security-groups --group-ids <sg-id> \
  --query 'SecurityGroups[0].IpPermissions[?ToPort==`2375` || ToPort==`2376`]'
# Debe devolver una lista vacía. Si no, es un hallazgo crítico.

# Dentro de la instancia: el daemon Docker responde y el sandbox puede correr un contenedor
docker info >/dev/null && docker run --rm hello-world

# Crédito de CPU restante (solo aplica a familias burstable t2/t3/t4g)
aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUCreditBalance \
  --dimensions Name=InstanceId,Value=<id> --start-time "$(date -u -d '-1 hour' +%FT%TZ)" \
  --end-time "$(date -u +%FT%TZ)" --period 300 --statistics Average
```

Si cualquiera de estos comandos no está disponible (por permisos IAM insuficientes del operador), repórtalo como bloqueo — no asumas que "probablemente está bien".
