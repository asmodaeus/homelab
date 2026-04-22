# Homelab Repo Notes

## Scope

- Dieses Repo verwaltet ein Raspberry-Pi-Homelab per Ansible + K3s + ArgoCD GitOps.
- Produktions-Bootstrap läuft über `ansible/playbooks/*.yaml`.
- Lokale Iteration läuft über `./dev/bootstrap-local.sh` mit k3d + Gitea.

## Wichtige Verzeichnisse

- `bootstrap/`: Root-App, App-of-Apps, ArgoCD-Self-Management, NFS-ApplicationSet.
- `infrastructure/`: Cluster-Basisdienste wie Traefik, MetalLB, Sealed Secrets.
- `apps/`: fachliche Workloads wie Paperless, Home Assistant, Zigbee2MQTT.
- `ansible/`: Host-Vorbereitung, K3s-Installation, ArgoCD-Bootstrap.
- `dev/`: lokaler k3d-Workflow und Smoke-Tests.
- `docs/`: Setup-, Betriebs- und Migrationsdoku.

## Arbeitsregeln

- Niemals Plaintext-Secrets, `kubeconfig`, `local.env` oder Schlüsselmaterial committen.
- Wenn du ArgoCD-Quellen anfasst, Branch-/Repo-Steuerung über das Cluster-Secret erhalten.
- Änderungen an Architektur oder Workflow immer auch in `MEMORY.md` und betroffener Doku nachziehen.
- Lokale Shell-Skripte mit `shellcheck dev/*.sh` und `shfmt -d dev/*.sh` prüfen.

## Relevante Checks

- `uvx --from yamllint yamllint -c .yamllint.yaml .`
- `ANSIBLE_ROLES_PATH='ansible/roles:~/.ansible/roles' uvx --from ansible-lint ansible-lint ansible/`
- `shellcheck dev/*.sh`
- `shfmt -d dev/*.sh`
- Nach lokalem Cluster-Bootstrap: `./dev/test-local.sh`
