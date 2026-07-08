#!/usr/bin/env bash
# Illustrative deploy script for the Azure VM path of azure-hermes-deploy.
# Not yet run end-to-end against a live subscription — review every command
# and adjust names/region/VM size before running against anything real.
set -euo pipefail

RG="${RG:-rg-hermes}"
LOCATION="${LOCATION:-eastus2}"
VM_NAME="${VM_NAME:-vm-hermes}"
VM_SIZE="${VM_SIZE:-Standard_B2ms}"
DISK_NAME="disk-hermes-data"
KEYVAULT="${KEYVAULT:-kv-hermes}"

MY_IP=$(curl -s ifconfig.me)

echo "==> Resource group"
az group create -n "$RG" -l "$LOCATION" >/dev/null

echo "==> VM (SSH locked to current IP: $MY_IP/32)"
az vm create -n "$VM_NAME" -g "$RG" \
  --image Ubuntu2204 --size "$VM_SIZE" \
  --admin-username hermes --generate-ssh-keys \
  --custom-data templates/cloud-init-vm.yaml \
  --assign-identity '[system]' \
  --nsg-rule SSH >/dev/null

az vm open-port -n "$VM_NAME" -g "$RG" --port 22 \
  --priority 100 --source-address-prefixes "${MY_IP}/32" >/dev/null

echo "==> Persistent data disk"
az disk create -n "$DISK_NAME" -g "$RG" --size-gb 32 --sku Premium_LRS >/dev/null
az vm disk attach -g "$RG" --vm-name "$VM_NAME" --name "$DISK_NAME" >/dev/null

echo "==> Grant the VM's managed identity access to Key Vault"
PRINCIPAL_ID=$(az vm identity show -g "$RG" -n "$VM_NAME" --query principalId -o tsv)
az keyvault create -n "$KEYVAULT" -g "$RG" -l "$LOCATION" >/dev/null 2>&1 || true
az role assignment create --assignee "$PRINCIPAL_ID" \
  --role "Key Vault Secrets User" \
  --scope "$(az keyvault show -n "$KEYVAULT" -g "$RG" --query id -o tsv)" >/dev/null

echo "==> Done. cloud-init installs Docker + Hermes and mounts the data disk"
echo "    at /mnt/hermes-data on first boot. Check progress with:"
echo "    az vm run-command invoke -g $RG -n $VM_NAME --command-id RunShellScript --scripts 'cloud-init status --wait'"
