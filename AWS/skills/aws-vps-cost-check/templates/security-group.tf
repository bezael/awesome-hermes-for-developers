# templates/security-group.tf
#
# Security group de referencia para una instancia EC2 que corre Hermes Agent
# con terminal.backend: docker. Punto de partida — ajusta el CIDR de admin_cidr
# y el puerto de la UI/API de Hermes según tu despliegue real. No es un módulo
# listo para producción sin revisión: úsalo como base, no como copiar-pegar ciego.
#
# Uso:
#   terraform plan -var="vpc_id=vpc-xxxx" -var="admin_cidr=203.0.113.4/32"

variable "vpc_id" {
  type        = string
  description = "VPC donde vive la instancia de Hermes."
}

variable "admin_cidr" {
  type        = string
  description = "CIDR /32 (o el rango de tu VPN corporativa) desde el que se administra por SSH. NUNCA 0.0.0.0/0."
}

variable "hermes_ui_port" {
  type        = number
  default     = 0
  description = "Puerto de la UI/API de Hermes si se expone directamente (0 = no crear la regla, recomendado si va detrás de un reverse proxy autenticado)."
}

resource "aws_security_group" "hermes_agent" {
  name        = "hermes-agent-sg"
  description = "SSH restringido + egress abierto para un host de Hermes Agent con sandbox Docker. Sin puertos de Docker daemon expuestos."
  vpc_id      = var.vpc_id

  # SSH de administración — SOLO desde admin_cidr, nunca 0.0.0.0/0.
  ingress {
    description = "SSH administrativo"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Egress abierto: llamadas a APIs de modelos LLM, registries npm/pypi/apt, git.
  # Restringe esto a 443/80/53 únicamente si sigues un baseline de hardening
  # más estricto que el default de este template.
  egress {
    description = "Todo el tráfico saliente (llamadas a APIs LLM, registries de paquetes, git)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # A propósito, NO hay reglas para 2375/2376 (Docker daemon TCP).
  # Si necesitas administrar Docker de forma remota, usa un túnel SSH
  # (ssh -L 2375:localhost:2375) o `docker context create --docker "host=ssh://..."`,
  # nunca expongas el daemon directamente a la red.

  tags = {
    Name    = "hermes-agent-sg"
    Purpose = "hermes-agent-docker-sandbox"
  }
}

# Regla opcional para la UI/API de Hermes, solo si hermes_ui_port != 0.
# Sigue restringida a admin_cidr — si necesitas acceso público, ponle
# autenticación propia delante (reverse proxy), no confíes solo en el
# security group como única barrera.
resource "aws_security_group_rule" "hermes_ui" {
  count             = var.hermes_ui_port != 0 ? 1 : 0
  type              = "ingress"
  description       = "UI/API de Hermes (restringida a admin_cidr)"
  from_port         = var.hermes_ui_port
  to_port           = var.hermes_ui_port
  protocol          = "tcp"
  cidr_blocks       = [var.admin_cidr]
  security_group_id = aws_security_group.hermes_agent.id
}
