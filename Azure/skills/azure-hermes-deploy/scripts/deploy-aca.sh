#!/usr/bin/env bash
# Illustrative deploy script for the Container Apps path of azure-hermes-deploy.
# Not yet run end-to-end against a live subscription — review every command
# and adjust names/region/image before running against anything real.
set -euo pipefail

RG="${RG:-rg-hermes}"
LOCATION="${LOCATION:-eastus2}"
ENV_NAME="${ENV_NAME:-env-hermes}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-sthermesdata}"
SHARE_NAME="hermes-state"
KEYVAULT="${KEYVAULT:-kv-hermes}"
APP_NAME="${APP_NAME:-hermes-agent}"
IMAGE="${IMAGE:?Set IMAGE to your Hermes container image, e.g. ghcr.io/yourorg/hermes-agent:latest}"

echo "==> Resource group + Container Apps environment"
az group create -n "$RG" -l "$LOCATION" >/dev/null
az containerapp env create -n "$ENV_NAME" -g "$RG" -l "$LOCATION" >/dev/null

echo "==> Persistent storage (Azure Files) for Hermes state"
az storage account create -n "$STORAGE_ACCOUNT" -g "$RG" -l "$LOCATION" --sku Standard_LRS >/dev/null
az storage share-rm create --storage-account "$STORAGE_ACCOUNT" -n "$SHARE_NAME" --quota 20 >/dev/null

STORAGE_KEY=$(az storage account keys list -n "$STORAGE_ACCOUNT" -g "$RG" --query '[0].value' -o tsv)

az containerapp env storage set \
  --name "$ENV_NAME" -g "$RG" \
  --storage-name hermes-state-storage \
  --azure-file-account-name "$STORAGE_ACCOUNT" \
  --azure-file-account-key "$STORAGE_KEY" \
  --azure-file-share-name "$SHARE_NAME" \
  --access-mode ReadWrite >/dev/null

echo "==> Key Vault for secrets (skip if it already exists)"
az keyvault create -n "$KEYVAULT" -g "$RG" -l "$LOCATION" >/dev/null 2>&1 || true

echo "==> Deploy the container app (uses templates/containerapp.bicep as reference)"
echo "    Review templates/containerapp.bicep, fill in storageAccountName/keyVaultName,"
echo "    then deploy with:"
echo ""
echo "    az deployment group create -g $RG --template-file templates/containerapp.bicep \\"
echo "      --parameters storageAccountName=$STORAGE_ACCOUNT keyVaultName=$KEYVAULT image=$IMAGE"
echo ""
echo "==> After deploy: grant the app's managed identity access to Key Vault"
echo "    PRINCIPAL_ID=\$(az containerapp show -n $APP_NAME -g $RG --query identity.principalId -o tsv)"
echo "    az role assignment create --assignee \"\$PRINCIPAL_ID\" \\"
echo "      --role \"Key Vault Secrets User\" \\"
echo "      --scope \$(az keyvault show -n $KEYVAULT -g $RG --query id -o tsv)"
