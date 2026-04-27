# Project Memory

Stand: 2026-04-27

## Zweck

- GitOps-Homelab fuer Raspberry Pi mit Ansible-Bootstrap und ArgoCD App-of-Apps.
- Lokaler Entwicklungsweg basiert auf k3d + Gitea, damit Branches ohne GitHub-Roundtrip getestet werden koennen.

## Aktueller Architekturstand

- `bootstrap/root-app.yaml` bleibt der manuelle Einstiegspunkt.
- `bootstrap/app-of-apps.yaml` erzeugt Apps fuer `local/`, `infrastructure/`, `config/`, `apps/` und optional `monitoring/`.
- `bootstrap/nfs-app.yaml` liest `nasIP` und `nasPath` aus dem ArgoCD-Cluster-Secret.
- `bootstrap/argocd/argocd-app.yaml` ist als `ApplicationSet` modelliert, damit die Self-Management-App dieselbe `repoURL` und `targetRevision` wie der aktive Cluster nutzt.
- Lokaler Bootstrap patcht nur noch `root-app.yaml`; die Self-Management-Quelle fuer ArgoCD folgt danach dem Cluster-Secret.
- Monitoring ist im App-of-Apps-Flow verdrahtet, bleibt aber hinter dem Cluster-Label `homelab-monitoring=enabled` verborgen.
- `monitoring/victoria-metrics/helmrelease.yaml` ist als `ApplicationSet` modelliert, damit die Values-Quelle fuer lokale Branches und Produktion aus denselben Cluster-Metadaten kommt.

## Bekannte offene Punkte

- TLS Phase 4 ist dokumentiert, aber `ClusterIssuer`/`Certificate`-Manifeste sind noch nicht im Repo angelegt.
- Mehrere Apps erwarten Sealed Secrets (`paperless-secrets`, `mosquitto-passwd`, `zigbee2mqtt-secrets`), die bewusst nicht im Repo vorliegen.
- Zigbee2MQTT nutzt bewusst `privileged` + `hostPath`, weil der USB-Adapter direkt am Pi haengt.
- Monitoring braucht vor Aktivierung weiterhin echte Grafana-Credentials statt Platzhalter.

## Validierung

- YAML: `uvx --from yamllint yamllint -c .yamllint.yaml .`
- Ansible: `ANSIBLE_ROLES_PATH='ansible/roles:~/.ansible/roles' uvx --from ansible-lint ansible-lint ansible/`
- Shell: `shellcheck dev/*.sh` und `shfmt -d dev/*.sh`
- Lokal: `./dev/bootstrap-local.sh` gefolgt von `./dev/test-local.sh`

## Naechste sinnvolle Verbesserungen

- Cert-Manager Phase 4 mit echten Manifests fuer Issuer, Certificate und Cloudflare-Secrets abschliessen.
- Grafana-Credentials fuer Monitoring vor produktiver Aktivierung via Secret/Sealed Secret sauber modellieren.
- Optional: kubeconform/kube-linter lokal per Dev-Skript oder Make-Target einfacher ausfuehrbar machen.
