# Homelab Kubernetes – Claude Kontext

Kubernetes-Homelab auf Raspberry Pi (ARM64/ARM32), verwaltet via GitOps.

## Hardware

| Node | Modell | RAM | Rolle |
|---|---|---|---|
| `pi4` | Pi 4 Model B | 2GB | K3s Control Plane + Worker |
| `pi3` | Pi 3 Model B V1.2 | 1GB | K3s Agent (light workloads only) |
| `pi-ha` | Pi 4 Model B | 2GB | K3s Agent (nach HA-Migration) |

Pi 3 hat `NoSchedule`-Taint `workload=light` – nur Pods mit expliziter Toleration laufen darauf
(aktuell: Zigbee2MQTT + Mosquitto, da USB-Zigbee-Adapter am Pi 3 hängt).

## Stack

- **K3s** (lightweight Kubernetes, ARM64)
- **ArgoCD** (App-of-Apps + ApplicationSets, GitOps)
- **Traefik v3** (Ingress / Gateway API)
- **MetalLB** (L2 Load Balancer, 192.168.1.200–210)
- **Sealed Secrets** (verschlüsselte Secrets in Git)
- **NFS Subdir External Provisioner** (NAS als primärer Storage, kein Longhorn nötig)
- **System Upgrade Controller** (automatische K3s-Updates via `stable` Channel)
- **Victoria Metrics + Grafana** (Monitoring, Phase 2)

## Apps

- **Paperless-ngx** – Dokumentenmanagement (NFS Storage, SQLite, eigenes `redis.yaml` statt Subchart)
- **Home Assistant** – Heimautomatisierung
- **Zigbee2MQTT** – Zigbee Bridge (nodeSelector: `homelab/zigbee-adapter=true` → Pi 3, nur Produktion)
- **Mosquitto** – MQTT Broker (Pi 3 mit Zigbee2MQTT, nur Produktion)

## Konventionen

- **Niemals** Plaintext-Secrets in Git → immer `kubeseal` verwenden
- Alle Änderungen via PR (nicht direkt auf `main`), immer vom `main`-Branch aus neuen Feature-Branch erstellen
- Versionen immer explizit pinnen (kein `latest`-Tag)
- Resource Limits auf allen Workloads setzen
- ARM64-Kompatibilität vor neuen Images prüfen (`docker manifest inspect <image>`)
- Pi 3 hat nur 1GB RAM – keine schweren Workloads ohne Toleration für `workload=light`

### Gateway API HTTPRoutes

Immer `group` und `kind` in `parentRefs` **und** `group`, `kind`, `weight` in `backendRefs` explizit setzen.
Kubernetes fügt diese Felder beim Apply als Defaults hinzu – ohne sie zeigt ArgoCD dauerhaft OutOfSync-Diffs.

```yaml
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: homelab
      namespace: traefik
      sectionName: web
  rules:
    - backendRefs:
        - group: ""
          kind: Service
          name: <service-name>
          port: <port>
          weight: 1
```

### Lokaler Cluster (k3d) vs. Produktion

Der k3d-Cluster simuliert die Produktionsumgebung, mit diesen Unterschieden:

| | Lokal (k3d) | Produktion (Pi) |
|---|---|---|
| Architektur | x86_64 | ARM64 |
| Git-Server | Gitea (in-cluster) | GitHub |
| NFS Storage | nicht verfügbar (local-path Fallback) | NAS |
| `mosquitto` | **nicht deployed** (kein USB-Adapter) | ✓ |
| `zigbee2mqtt` | **nicht deployed** (kein USB-Adapter) | ✓ |
| k3s-Upgrade-Plans | **nicht deployed** (`homelab-env=local`) | ✓ |

Node-Labels und -Taints für den k3d-Agenten sind deklarativ in `dev/k3d-config.yaml` definiert (via k3s extraArgs), nicht im Bootstrap-Script.

## Lokale Entwicklung

```bash
# Cluster starten (Gitea + ArgoCD, aktueller Branch wird deployed)
./dev/bootstrap-local.sh
REVISION=my-feature-branch ./dev/bootstrap-local.sh  # anderen Branch testen

# Änderungen deployen (ArgoCD synct in ~30s)
git add -A && git commit -m "my change"
git push local

# Tests ausführen
./dev/test-local.sh

# Cluster abbauen
./dev/teardown-local.sh
```

**Slash-Commands** (in Claude Code Sessions verfügbar):
- `/bootstrap` – Cluster starten
- `/argocd-status` – App-Status anzeigen
- `/lint` – Lokale Linter ausführen

## CI / Integration Test

Der Workflow `.github/workflows/ci-integration.yaml` startet ein k3d-Cluster in GitHub Actions:

- **Trigger**: Nur manuell – GitHub Actions UI → "Integration Test" → "Run workflow"
- **`revision`-Input**: Branch, Tag oder SHA zum Testen
- **Wann vorschlagen**: Bei Änderungen an `bootstrap/`, `dev/`, `infrastructure/`, `apps/` oder `.github/workflows/` – nicht bei Docs, Lint-Fixes oder Kommentaren
- **Voraussetzung**: Workflow muss auf `main` liegen um in der GitHub Actions UI zu erscheinen

`dev/bootstrap-local.sh` unterstützt `CI=true` (überspringt Gitea, ArgoCD zeigt auf GitHub statt Gitea).

**GitHub MCP-Einschränkung**: Die MCP-Tools haben keinen `workflow_dispatch`-Endpoint – Trigger nur über die GitHub Actions UI oder `gh workflow run` auf dem lokalen Rechner des Users. Check-Run-Ergebnisse können via MCP ausgelesen werden (`mcp__github__pull_request_read` mit `get_check_runs`).

## Wichtige Dateien

| Datei | Bedeutung |
|---|---|
| `bootstrap/root-app.yaml` | Einzige manuell angewendete Ressource – Schlüsselstein des GitOps-Systems |
| `dev/k3d-config.yaml` | k3d-Cluster-Konfiguration inkl. Node-Labels/Taints für Agent |
| `dev/bootstrap-local.sh` | Lokaler Bootstrap + `CI=true`-Modus für GitHub Actions |
| `ansible/inventory/hosts.yaml` | Pi-IPs und Rollen (muss vor Bootstrap ausgefüllt sein) |
| `infrastructure/metallb/ip-address-pool.yaml` | MetalLB IP-Range (im Router-DHCP ausschließen!) |
| `infrastructure/nfs-provisioner/values.yaml` | NAS-IP + NFS-Pfad (vor Phase 2 ausfüllen) |
| `apps/home-assistant/zigbee2mqtt/deployment.yaml` | USB-Device-Path (muss mit `ls /dev/ttyUSB* /dev/ttyACM*` geprüft werden) |
| `apps/paperless-ngx/redis.yaml` | Standalone Redis (kein Helm-Subchart – Bitnami-Images nicht auf Docker Hub verfügbar) |

## Befehle

```bash
# Cluster-Status
kubectl get nodes -o wide
kubectl get pods -A

# ArgoCD Apps
kubectl -n argocd get applications

# Secrets versiegeln
kubeseal --format yaml < secret.yaml > sealed-secret.yaml

# K3s-Node-Labels setzen (nach Bootstrap)
kubectl label node <pi3-hostname> workload=light
kubectl taint node <pi3-hostname> workload=light:NoSchedule
kubectl label node <pi3-hostname> homelab/zigbee-adapter=true
```

## Sync Waves (ArgoCD)

- Wave `-3`: MetalLB (muss vor Traefik laufen)
- Wave `-2`: Traefik, cert-manager, Sealed Secrets, NFS Provisioner
- Wave `-1`: System Upgrade Controller
- Wave `0`: Apps (Paperless-ngx, Home Assistant Stack)
- Wave `1`: Monitoring (Phase 2)
