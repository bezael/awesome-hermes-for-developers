# Container Apps vs Azure VM for Hermes Agent

Decision reference for `azure-hermes-deploy`. Use this before running any of
the scripts/templates in this skill.

## At a glance

| Dimension | Azure Container Apps | Azure VM |
|---|---|---|
| Native `terminal.backend: docker` sandbox | No (Consumption plan has no privileged containers / Docker socket) | Yes, works out of the box |
| Scale to zero | Yes (breaks long-polling channels — see Pitfalls) | No — you pay for the VM whether Hermes is busy or idle |
| Managed HTTPS ingress | Built in | You configure it (Nginx/Caddy + cert-manager or Azure App Gateway) |
| Ops overhead | Low — no OS patching, no systemd units to maintain | Higher — you own the host |
| Persistent state | Azure Files volume mount | Managed Disk or Azure Files |
| Cost floor for a personal/low-traffic bot | Near-zero if scale-to-zero is viable | Fixed VM cost even when idle (B-series is cheap but not free) |
| Root/system access for skills that shell out (`apt`, `systemctl`, kernel modules) | No | Yes |
| Nested virtualization (Firecracker/microVM sandbox backends) | Not applicable | Only on `Dv3`/`Ev3`/`Dv4`/`Ev4`+ families — not on `B`-series |

## Recommendation flow

1. Does the user need the Docker sandbox (`terminal.backend: docker`) or
   root-level system access for skills? → **VM**.
2. Is it a personal/low-traffic assistant reachable over a webhook-based
   channel (not long-polling)? → **Container Apps**, scale-to-zero is fine.
3. Is it reachable over a long-polling channel (Telegram/Discord gateway)
   but still doesn't need the Docker sandbox? → **Container Apps** with
   `minReplicas: 1`.
4. Unsure / user hasn't specified? → Default to **Container Apps** for a
   first deployment; it's cheaper to get wrong and migrate away from than a
   VM you have to decommission.

## What Container Apps genuinely cannot do (as of this skill's writing)

- Mount `/var/run/docker.sock` or run privileged containers on the
  Consumption plan — nested Docker sandboxing is off the table.
- If the user specifically wants an isolated code-execution sandbox on
  Container Apps rather than a VM, the correct answer is **Azure Container
  Apps dynamic sessions** (a separate Hyper-V–isolated sessions pool
  product), not trying to force Docker-in-Docker into a regular container
  app. Verify current availability/GA status for the user's region before
  committing to this path — it has been rolling out gradually.
