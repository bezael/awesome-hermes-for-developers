---
name: azure-hermes-deploy
description: Deploy Hermes Agent to Azure — either Azure Container Apps (ACA) or an Azure Linux VM — with persistent state volumes, secrets pulled from Key Vault instead of baked into the image, and the agent's isolated sandbox configured correctly for whichever target you pick. Use when a user wants to run Hermes on Azure specifically (not a generic VPS, not AWS/GCP) and asks about hosting, persistence, secrets, or sandboxing on ACA or an Azure VM.
version: 0.1.0
author: dominicode
platforms: [linux]
metadata:
  hermes:
    tags: [azure, deploy, container-apps, vm, terraform, bicep, sandbox, secrets, key-vault]
    category: devops
---

# Azure Hermes Deploy

> **Status: illustrative, not yet run against a live Hermes instance.**
> Every command below is technically grounded in real Azure CLI / Bicep syntax,
> but this skill has not been executed end-to-end against a production Hermes
> Agent deployment yet. Treat the Bicep/cloud-init/scripts in this folder as a
> verified-on-paper starting point — validate resource names, API versions and
> current Azure feature availability (some, like Container Apps dynamic
> sessions, are still rolling out region by region) against the official docs
> before running this against anything that matters.

## When to Use

- The user wants to host Hermes Agent on **Azure** specifically — not a
  generic VPS, not AWS/GCP (see `hermes-agent-cloud` type multi-cloud tools
  for that).
- They're deciding between **Azure Container Apps** (serverless, scale
  based, managed ingress/TLS) and an **Azure VM** (full host control, native
  Docker sandbox, always-on background process).
- They need Hermes' state (SQLite memory DB, skills cache, conversation
  history, uploaded files) to **survive restarts and revisions** instead of
  living inside an ephemeral container filesystem.
- They need to store provider API keys, channel tokens (Telegram/Discord/
  Slack), and webhook secrets **outside the container image and outside
  git** — pulled at runtime from Azure Key Vault.
- They want Hermes' isolated sandbox (`terminal.backend: docker` or a
  microVM-based backend) actually working inside Azure's container/VM
  boundary, instead of silently falling back to an unsandboxed subprocess.

## Procedure

### 1. Pick the target: ACA vs VM

Read `references/aca-vs-vm-decision-matrix.md` for the full comparison.
Short version:

| Need | Use |
|---|---|
| Scale to zero, managed HTTPS ingress, no ops overhead | **Container Apps** |
| Native `terminal.backend: docker` sandbox (nested containers) | **VM** |
| Always-on long-polling channel (Telegram/Discord) | Either, but ACA needs `minReplicas: 1` |
| Full host access for skills that shell out to system tools (`apt`, `systemctl`) | **VM** |
| Fastest path to "it's running somewhere" for a personal assistant | **Container Apps** |

If the user hasn't said which they want and their use case doesn't clearly
point one way, default to recommending **Container Apps** for a personal/low
-traffic Hermes and reserve the **VM** recommendation for cases where they
explicitly need the Docker sandbox or root-level system access.

### 2. Container Apps path

1. Resource group, environment, storage:
   ```bash
   az group create -n rg-hermes -l eastus2
   az containerapp env create -n env-hermes -g rg-hermes -l eastus2
   ```
2. Create a storage account + Azure Files share for persistent state, then
   register it on the environment:
   ```bash
   az storage account create -n sthermesdata -g rg-hermes -l eastus2 --sku Standard_LRS
   az storage share-rm create --storage-account sthermesdata -n hermes-state --quota 20
   az containerapp env storage set \
     --name env-hermes -g rg-hermes \
     --storage-name hermes-state-storage \
     --azure-file-account-name sthermesdata \
     --azure-file-account-key "$(az storage account keys list -n sthermesdata -g rg-hermes --query '[0].value' -o tsv)" \
     --azure-file-share-name hermes-state \
     --access-mode ReadWrite
   ```
3. Mount that storage as a volume in the container app pointing at Hermes'
   state directory (default `~/.hermes` inside the container — adjust to
   wherever `HERMES_HOME` is set). See `templates/containerapp.bicep` for the
   full `volumes` / `volumeMounts` wiring.
4. Reference secrets from Key Vault instead of plain env vars (see step 4)
   and deploy:
   ```bash
   az containerapp create \
     --name hermes-agent -g rg-hermes \
     --environment env-hermes \
     --image ghcr.io/yourorg/hermes-agent:latest \
     --min-replicas 1 --max-replicas 1 \
     --cpu 0.5 --memory 1.0Gi \
     --yaml templates/containerapp.bicep
   ```
5. **`minReplicas: 1`, not 0** — if Hermes is wired to a long-polling
   channel (Telegram/Discord gateway), scale-to-zero drops the connection
   and the bot goes silent until the next inbound HTTP request wakes the
   revision back up. Only allow scale-to-zero if the channel is a webhook
   (inbound HTTP), not long-polling.

### 3. Azure VM path

1. Provision an Ubuntu 22.04 LTS VM with a locked-down NSG (SSH from your
   IP only) and an attached managed data disk for persistence:
   ```bash
   az vm create -n vm-hermes -g rg-hermes \
     --image Ubuntu2204 --size Standard_B2ms \
     --admin-username hermes --generate-ssh-keys \
     --nsg-rule SSH
   az vm open-port -n vm-hermes -g rg-hermes --port 22 \
     --priority 100 --source-address-prefixes "$(curl -s ifconfig.me)/32"
   az disk create -n disk-hermes-data -g rg-hermes --size-gb 32 --sku Premium_LRS
   az vm disk attach -g rg-hermes --vm-name vm-hermes --name disk-hermes-data
   ```
2. Use `templates/cloud-init-vm.yaml` (pass via `--custom-data` on
   `az vm create`, or run manually post-boot) to: format/mount the data
   disk at `/mnt/hermes-data`, install Docker, install Hermes, and register
   it as a `systemd --user` service that survives reboot.
3. Native sandbox: on a VM you have a real kernel, so
   `terminal.backend: docker` works normally — no nested-virtualization
   dance required for plain Docker containers. Nested virtualization (KVM
   passthrough) is only a concern if the sandbox backend itself needs to
   spin up microVMs (e.g. Firecracker); in that case pick a VM size from
   the `Dv3`/`Ev3`/`Dv4`/`Ev4` families or newer, which support nested
   virtualization on Azure — most `B`-series burstable VMs do not.
4. Bind the persistent disk into the Hermes state path (either directly if
   Hermes runs on the host, or as a bind mount into the sandbox container
   if it runs inside Docker) so memory/skills survive VM reboots.

### 4. Secrets: Key Vault, not plain env vars

- Create the vault and secrets once:
  ```bash
  az keyvault create -n kv-hermes -g rg-hermes -l eastus2
  az keyvault secret set --vault-name kv-hermes -n openai-api-key --value "sk-..."
  az keyvault secret set --vault-name kv-hermes -n telegram-bot-token --value "123:abc"
  ```
- **Container Apps**: enable a system-assigned managed identity on the
  container app, grant it the **`Key Vault Secrets User`** role (not
  Administrator — least privilege) on the vault, then reference secrets by
  Key Vault URI instead of raw value:
  ```bash
  az containerapp identity assign --name hermes-agent -g rg-hermes --system-assigned
  az containerapp secret set --name hermes-agent -g rg-hermes \
    --secrets openai-api-key=keyvaultref:https://kv-hermes.vault.azure.net/secrets/openai-api-key,identityref:system
  ```
  Then wire `env: [{ name: OPENAI_API_KEY, secretRef: openai-api-key }]` in
  the container app spec — the raw secret value never appears in the
  Bicep/YAML, in `az containerapp show`, or in CI logs.
- **VM**: assign a system-assigned managed identity to the VM, grant the
  same `Key Vault Secrets User` role, and pull secrets at boot time in
  `cloud-init-vm.yaml` via `az keyvault secret show` into an
  `EnvironmentFile=` consumed by the systemd unit — never commit a plain
  `.env` to the repo, and `chmod 600` it if one exists on disk at all.

### 5. Verify the sandbox is actually isolated, not silently disabled

Whichever target you chose, don't assume the sandbox config took — Hermes
falls back to an unsandboxed subprocess on some backends if the requested
one isn't available, and that failure mode is easy to miss. See
`references/hermes-config-azure.md` for the exact config block per target,
and the Verification section below for how to confirm it's really enforced.

## Pitfalls

- **ACA Consumption plan cannot run privileged containers or mount the
  Docker socket** — `terminal.backend: docker` inside a plain ACA
  container will fail to start the sandbox (or silently no-op, depending on
  Hermes' fallback config). If the user needs nested Docker sandboxing on
  ACA specifically, point them at **Azure Container Apps dynamic sessions**
  (a separate, Hyper-V–isolated sessions pool built for exactly this kind of
  code-execution sandboxing) rather than trying to force Docker-in-Docker
  into a regular container app — and flag that this feature's availability
  varies by region/subscription, so check current docs first.
- **Azure Files (SMB) + SQLite state store is a bad combination.** SMB's
  file-locking semantics don't play well with SQLite's locking model under
  concurrent access — expect intermittent "database is locked" errors.
  Prefer Azure Files **NFS 4.1** (Premium/FileStorage tier only) or a
  Managed Disk (VM path) for the state directory; only use SMB for
  read-mostly assets.
- **`minReplicas: 0` silently breaks long-polling channels.** The bot looks
  "dead" with no error in the logs — it's just descaled. Always set
  `minReplicas: 1` for Telegram/Discord-style long-polling bots on ACA.
- **Over-scoped Key Vault RBAC.** Granting `Key Vault Administrator` to the
  container app / VM identity instead of `Key Vault Secrets User` means a
  compromised Hermes instance could rotate or delete every secret in the
  vault, not just read the ones it needs.
- **Open NSG on the VM path.** Defaulting to `--nsg-rule SSH` without also
  restricting the source IP leaves port 22 (and, if the Hermes web
  dashboard is bound to `0.0.0.0`, the dashboard port too) open to the
  entire internet. Lock both to the operator's current IP or a VPN range.
- **Baking secrets into the container image or Bicep parameter files.**
  Any `param openaiApiKey string = 'sk-...'` committed to the repo defeats
  the entire point of using Key Vault — always pass secrets by reference,
  never by value, in source-controlled files.

## Verification

- **ACA is actually running:**
  `az containerapp show -n hermes-agent -g rg-hermes --query properties.runningStatus`
  should report `Running`; `az containerapp revision list -n hermes-agent -g rg-hermes`
  should show the active revision as `Healthy`.
- **Persistence survives a restart:** trigger
  `az containerapp revision restart` (ACA) or `az vm restart` (VM), then
  confirm Hermes' memory/skills state is unchanged — ask it something that
  depends on prior conversation history or a previously installed skill.
- **Secrets are references, not values:** `az containerapp show` (or
  `cat` the systemd `EnvironmentFile` path on the VM) should show
  `keyvaultref:...` / a Key Vault URI, never the literal secret string.
- **Sandbox is enforced, not bypassed:** ask Hermes to run a shell command
  through its sandbox and confirm it cannot see or modify files outside the
  mounted state volume (e.g. it can't read `/etc/shadow` or reach the host's
  other containers). If it can, the sandbox backend didn't actually engage
  — re-check step 5 and the Pitfalls entry on ACA + Docker.
- **NSG / ingress lockdown:** from a machine outside the allowed IP range,
  confirm SSH (VM) or the Hermes dashboard port is unreachable.
