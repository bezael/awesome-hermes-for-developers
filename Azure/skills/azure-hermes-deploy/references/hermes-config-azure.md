# Hermes config snippets per Azure target

Illustrative `hermes.config.yaml` (or equivalent env-var) fragments for each
deployment target covered by this skill. Adjust key names to whatever your
Hermes Agent version actually expects — check `hermes config --help` /
the config schema shipped with your install before copying these verbatim.

## Container Apps (no Docker sandbox available)

```yaml
terminal:
  backend: subprocess   # Docker-in-Docker is not available on ACA Consumption
  restricted: true      # deny network/filesystem access outside the mounted volume
state:
  path: /mnt/hermes-state   # Azure Files volume mount point
  db: sqlite               # only if the share is mounted NFS 4.1, not SMB — see Pitfalls
secrets:
  openai_api_key: ${OPENAI_API_KEY}     # populated via secretRef -> Key Vault
  telegram_bot_token: ${TELEGRAM_BOT_TOKEN}
channel:
  telegram:
    mode: long-polling   # requires minReplicas: 1, see containerapp.bicep
```

## Azure VM (native Docker sandbox available)

```yaml
terminal:
  backend: docker
  docker:
    socket: /var/run/docker.sock
    image: hermes-sandbox:latest
    network: none          # no outbound network from inside the sandbox unless a skill needs it
    read_only_root: true
    mounts:
      - source: /mnt/hermes-data
        target: /root/.hermes
        mode: rw
state:
  path: /mnt/hermes-data
  db: sqlite
secrets:
  openai_api_key: ${OPENAI_API_KEY}     # populated by cloud-init from Key Vault at boot
  telegram_bot_token: ${TELEGRAM_BOT_TOKEN}
channel:
  telegram:
    mode: long-polling   # fine on a VM, nothing scales to zero
```

## Checking the sandbox actually engaged

After startup, Hermes should log which `terminal.backend` it resolved to —
if you asked for `docker` and it logged a fallback to `subprocess` (or
similar), the sandbox did not engage and shell commands are running
unsandboxed on the host/container. Treat that as a deploy failure, not a
warning to ignore.
