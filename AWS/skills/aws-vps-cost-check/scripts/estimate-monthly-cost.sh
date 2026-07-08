#!/usr/bin/env bash
#
# estimate-monthly-cost.sh — Costo mensual estimado de una instancia EC2 + EBS gp3
# para un despliegue de Hermes Agent con sandbox Docker, usando la AWS Pricing API
# EN VIVO (nunca una tabla de precios memorizada, que se desactualiza).
#
# Uso:
#   scripts/estimate-monthly-cost.sh <instance-type> [region] [ebs-gb]
#
# Ejemplo:
#   scripts/estimate-monthly-cost.sh t4g.medium us-east-1 40
#
# Requiere: aws CLI v2 autenticado, jq. Permiso IAM: pricing:GetProducts.
# Nota: la AWS Pricing API solo responde en el endpoint de us-east-1,
# sin importar la región de la instancia que estás consultando — eso es
# normal, no un error de este script.

set -euo pipefail

INSTANCE_TYPE="${1:-}"
REGION="${2:-us-east-1}"
EBS_GB="${3:-40}"

if [[ -z "$INSTANCE_TYPE" ]]; then
  echo "Uso: $0 <instance-type> [region] [ebs-gb]" >&2
  echo "Ejemplo: $0 t4g.medium us-east-1 40" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Falta 'jq'. Instálalo antes de correr este script (ej. apt install jq)." >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "Falta 'aws' (AWS CLI v2). Instálalo y corre 'aws configure' antes de continuar." >&2
  exit 1
fi

# La AWS Pricing API identifica regiones por nombre humano ("US East (N. Virginia)"),
# no por código de región. Mapa cubre las regiones más comunes para este caso de uso;
# agrega más filas si tu región no está aquí (ver la lista completa en
# https://aws.amazon.com/ec2/pricing/on-demand/ bajo el selector de región).
declare -A REGION_NAMES=(
  [us-east-1]="US East (N. Virginia)"
  [us-east-2]="US East (Ohio)"
  [us-west-1]="US West (N. California)"
  [us-west-2]="US West (Oregon)"
  [eu-west-1]="EU (Ireland)"
  [eu-central-1]="EU (Frankfurt)"
  [sa-east-1]="South America (Sao Paulo)"
)

LOCATION="${REGION_NAMES[$REGION]:-}"
if [[ -z "$LOCATION" ]]; then
  echo "Región '$REGION' no está en el mapa local de este script." >&2
  echo "Regiones soportadas: ${!REGION_NAMES[*]}" >&2
  echo "Agrega el nombre humano exacto de tu región (tal como aparece en la Pricing API) y vuelve a intentar." >&2
  exit 1
fi

echo "Consultando AWS Pricing API para '$INSTANCE_TYPE' en '$LOCATION' ($REGION)..." >&2

PRICE_JSON=$(aws pricing get-products \
  --service-code AmazonEC2 \
  --region us-east-1 \
  --filters \
    "Type=TERM_MATCH,Field=instanceType,Value=${INSTANCE_TYPE}" \
    "Type=TERM_MATCH,Field=location,Value=${LOCATION}" \
    "Type=TERM_MATCH,Field=operatingSystem,Value=Linux" \
    "Type=TERM_MATCH,Field=tenancy,Value=Shared" \
    "Type=TERM_MATCH,Field=preInstalledSw,Value=NA" \
    "Type=TERM_MATCH,Field=capacitystatus,Value=Used" \
  --query 'PriceList[0]' --output text)

if [[ -z "$PRICE_JSON" || "$PRICE_JSON" == "None" ]]; then
  echo "No se encontró precio on-demand para '$INSTANCE_TYPE' en '$LOCATION'." >&2
  echo "Verifica que el nombre de la instancia y la región sean correctos, o consulta manualmente:" >&2
  echo "https://aws.amazon.com/ec2/pricing/on-demand/" >&2
  exit 1
fi

HOURLY=$(echo "$PRICE_JSON" | jq -r '
  .terms.OnDemand
  | to_entries[0].value.priceDimensions
  | to_entries[0].value.pricePerUnit.USD
')

if [[ -z "$HOURLY" || "$HOURLY" == "null" ]]; then
  echo "No se pudo extraer el precio por hora de la respuesta de la Pricing API." >&2
  echo "Respuesta cruda guardada arriba — revísala manualmente si esto persiste." >&2
  exit 1
fi

# gp3: $0.08/GB-mes es la tarifa de ejemplo que AWS publica en aws.amazon.com/ebs/pricing
# (verificado julio 2026). Es una tarifa de EJEMPLO en la página oficial, no garantizada
# para tu región — confirma en la Pricing Calculator si el número final te importa.
EBS_RATE_PER_GB="0.08"

awk -v hourly="$HOURLY" -v ebs_gb="$EBS_GB" -v ebs_rate="$EBS_RATE_PER_GB" \
    -v instance="$INSTANCE_TYPE" -v region="$REGION" '
BEGIN {
  monthly_compute = hourly * 730
  monthly_ebs = ebs_gb * ebs_rate
  total = monthly_compute + monthly_ebs

  printf "\n=== Estimado mensual: %s (%s) ===\n", instance, region
  printf "Cómputo (on-demand, 730h/mes): $%.4f/h -> $%.2f/mes\n", hourly, monthly_compute
  printf "EBS gp3 (%d GB @ $%.2f/GB-mes, tarifa de ejemplo AWS): $%.2f/mes\n", ebs_gb, ebs_rate, monthly_ebs
  printf "TOTAL ESTIMADO: $%.2f/mes\n", total
  printf "\nNo incluye: transferencia de datos, Elastic IP inactiva, snapshots, ni Savings Plans/RIs.\n"
  printf "Precio de cómputo consultado en vivo contra la AWS Pricing API — precio de EBS es una tarifa de ejemplo, verifícala.\n"
}'
