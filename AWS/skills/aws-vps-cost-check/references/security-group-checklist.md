# Checklist de security groups para una instancia Hermes (sandbox Docker)

Aplica esto contra un grupo existente (`aws ec2 describe-security-groups --group-ids <sg-id>`) o úsalo para armar uno nuevo con `templates/security-group.tf` como base.

## Inbound (entrante)

| Puerto | Propósito | Origen correcto | Hallazgo si está mal |
|---|---|---|---|
| 22 (SSH) | Administración | La IP/CIDR específica del operador (`x.x.x.x/32`) o el CIDR de una VPN corporativa | `0.0.0.0/0` — el hallazgo más común y más crítico. Un bot escaneando internet lo encuentra en minutos, no en días. |
| Puerto de UI/API de Hermes (si está expuesto) | Acceso al dashboard/API del agente | IPs conocidas del operador, o detrás de un reverse proxy con autenticación propia (no confíes solo en el security group como única capa) | Abierto a `0.0.0.0/0` sin autenticación adicional delante. |
| 2375/2376 (Docker daemon TCP) | — | **Nunca debería estar en la lista de reglas inbound, ni siquiera restringido a una IP**, salvo un caso muy específico de administración remota con TLS mutuo configurado explícitamente | Cualquier regla que mencione estos puertos es un hallazgo — usa `docker context` sobre SSH o un túnel SSH (`ssh -L`) en vez de exponer el daemon a la red. |
| Cualquier rango amplio (`0-65535`, `1000-9000`, etc.) | — | No debería existir | "Por si acaso" no es una regla de seguridad — cada puerto abierto debe tener un propósito declarado. |

## Outbound (saliente)

Para este caso de uso (Hermes llamando APIs de modelos LLM, registries de paquetes npm/pypi/apt, y repos git), **allow-all outbound es aceptable** — no hay necesidad de restringir egress salvo que el operador siga un baseline de hardening más estricto (ej. compliance corporativo), en cuyo caso:

- Permite 443 (HTTPS) y 80 (HTTP para redirects) hacia cualquier destino.
- Permite 53 (DNS) si usas un resolver que lo requiera explícitamente.
- No hay necesidad de abrir rangos de puertos altos salientes — las conexiones salientes normales usan el mecanismo de *ephemeral ports* del sistema operativo, que el firewall de estado (stateful) de un security group ya maneja automáticamente para el tráfico de retorno.

## Verificación rápida con AWS CLI

```bash
# Todas las reglas inbound de un grupo, de un vistazo
aws ec2 describe-security-groups --group-ids <sg-id> \
  --query 'SecurityGroups[0].IpPermissions[].{Port:ToPort,Proto:IpProtocol,CIDRs:IpRanges[].CidrIp}'
```

Revisa cada fila contra la tabla de arriba. Cualquier CIDR `0.0.0.0/0` en un puerto que no sea explícitamente público (por ejemplo, 443 de un sitio web real) es candidato a hallazgo — repórtalo con el puerto y el CIDR exactos, no con un "revisa tus security groups" genérico.
