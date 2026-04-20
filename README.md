# homelab

Kubernetes-Homelab auf Raspberry Pi, verwaltet via GitOps (ArgoCD).

## Hardware

| Node | Modell | RAM | Rolle |
|---|---|---|---|
| `pi4` | Raspberry Pi 4 Model B | 2 GB | K3s Control Plane + Worker |
| `pi3` | Raspberry Pi 3 Model B V1.2 | 1 GB | K3s Agent (leichte Workloads) |

## Stack

| Bereich | Technologie |
|---|---|
| Kubernetes | [K3s](https://k3s.io/) |
| Provisioning | [Ansible](https://www.ansible.com/) + [k3s-ansible](https://github.com/k3s-io/k3s-ansible) |
| GitOps | [ArgoCD](https://argoproj.github.io/cd/) (App-of-Apps) |
| Ingress | [Traefik v3](https://traefik.io/) (Gateway API) |
| Load Balancer | [MetalLB](https://metallb.universe.tf/) (Layer 2) |
| Storage | NFS Subdir External Provisioner (NAS) |
| Secrets | [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) |
| Updates | [System Upgrade Controller](https://github.com/rancher/system-upgrade-controller) |
| Monitoring | [Victoria Metrics](https://victoriametrics.com/) + [Grafana](https://grafana.com/) (Phase 2) |

## Apps

- **[Paperless-ngx](https://docs.paperless-ngx.com/)** – Dokumentenmanagement
- **[Home Assistant](https://www.home-assistant.io/)** – Heimautomatisierung
- **[Zigbee2MQTT](https://www.zigbee2mqtt.io/)** + **[Mosquitto](https://mosquitto.org/)** – Zigbee-Integration

## Phasen

| Phase | Inhalt | Status |
|---|---|---|
| 1 | K3s-Cluster + ArgoCD + MetalLB + Traefik | 🔧 In Arbeit |
| 2 | Paperless-ngx + Monitoring + Sealed Secrets | 📋 Geplant |
| 3 | Home Assistant Migration (HA-Pi → Cluster) | 📋 Geplant |
| 4 | TLS + externe Erreichbarkeit | 📋 Geplant |

---

## Produktions-Bootstrap (Pi-Cluster)

Voraussetzungen:
- Alle Pis mit **64-bit OS** (Raspberry Pi OS Lite 64-bit)
- SSH-Key-Auth konfiguriert
- Statische DHCP-Leases für alle Pis im Router
- MetalLB IP-Range (z.B. 192.168.1.200–210) aus DHCP-Pool ausgeschlossen

```bash
# 1. Ansible-Dependencies installieren
cd ansible
ansible-galaxy install -r requirements.yaml

# 2. Inventory ausfüllen
vim inventory/hosts.yaml

# 3. OS vorbereiten (cgroups, SSH-Hardening)
ansible-playbook playbooks/os-prep.yaml

# 4. K3s installieren
ansible-playbook playbooks/k3s-install.yaml

# 5. Kubeconfig kopieren
scp pi@<pi4-ip>:~/.kube/config ~/.kube/config
kubectl get nodes

# 6. ArgoCD bootstrappen (setzt Cluster-Secret mit repoURL + homelab-env: production)
ansible-playbook playbooks/argocd-bootstrap.yaml

# 7. Root-App anwenden (einmalig manuell)
kubectl apply -f bootstrap/root-app.yaml
```

Nach Schritt 7 übernimmt ArgoCD die gesamte Verwaltung des Clusters via Git.

## Node-Labels nach Bootstrap

```bash
# Pi 3: leichte Workloads, Zigbee-Adapter
kubectl label node <pi3-hostname> workload=light
kubectl taint node <pi3-hostname> workload=light:NoSchedule
kubectl label node <pi3-hostname> homelab/zigbee-adapter=true
```

---

## Lokale Entwicklung (k3d)

Für schnelle Iteration ohne GitHub-Roundtrip: ein lokales k3d-Cluster mit
[Gitea](https://gitea.com/) als Git-Server. ArgoCD im Cluster zieht Code
direkt aus dem lokalen Gitea – kein Commit auf GitHub nötig.

### Voraussetzungen

```bash
brew install k3d kubectl helm docker jq git
```

### Ersteinrichtung

```bash
# Repo klonen
git clone https://github.com/asmodaeus/homelab.git
cd homelab

# Feature-Branch erstellen
git checkout -b feat/meine-aenderung

# Lokales Cluster starten (installiert k3d, Gitea, ArgoCD, bootstrapt alles)
./dev/bootstrap-local.sh
```

Das Skript:
1. Erstellt ein k3d-Cluster (`homelab`)
2. Installiert Gitea als lokalen Git-Server (`http://localhost:3000`)
3. Erstellt das Repo in Gitea und pusht den aktuellen Branch
4. Installiert ArgoCD
5. Setzt das Cluster-Secret mit `repoURL` (Gitea) + `targetRevision` (Branch)
6. Wendet die Root-App an – ArgoCD synct den gesamten Stack

Nach ca. 5–10 Minuten ist alles bereit:

```
╔════════════════════════════════════════════════════════════════════╗
║           Lokales Homelab-Cluster ist bereit!                      ║
╠════════════════════════════════════════════════════════════════════╣
║  Gitea:    http://localhost:3000   (gitea / gitea)                 ║
║  ArgoCD:   kubectl port-forward -n argocd svc/argocd-server 8080:80║
║            → http://localhost:8080  (admin / <auto-generiert>)     ║
╚════════════════════════════════════════════════════════════════════╝
```

### Entwicklungs-Loop

Änderungen werden durch einen lokalen Push sofort in ArgoCD sichtbar –
kein Push auf GitHub erforderlich:

```bash
# 1. Code ändern
vim infrastructure/traefik/helmrelease.yaml

# 2. Committen und nach Gitea pushen (ArgoCD synct in ~30 Sekunden)
git add -A
git commit -m "feat: ..."
git push local

# 3. Status beobachten
kubectl -n argocd get applications
# oder: ArgoCD UI unter http://localhost:8080
```

> **Tipp:** `REVISION=<branch-name> ./dev/bootstrap-local.sh` startet das
> Cluster direkt auf einem anderen Branch.

### Anderen Branch testen

```bash
REVISION=feat/anderer-branch ./dev/bootstrap-local.sh
```

### Fertig: Push auf GitHub und Pull Request

Wenn die Änderungen lokal funktionieren:

```bash
# Auf GitHub pushen
git push origin feat/meine-aenderung

# Pull Request erstellen (gh CLI)
gh pr create --title "feat: ..." --body "..."
```

### Cluster aufräumen

```bash
./dev/teardown-local.sh
# oder manuell:
k3d cluster delete homelab
git remote remove local
```

---

## Secrets verwalten

```bash
# Secret erstellen und versiegeln
kubectl create secret generic my-secret \
  --from-literal=key=value \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > sealed-secret.yaml

# Dann: sealed-secret.yaml in Git committen, original NICHT!
```

---

## Architektur

```
bootstrap/root-app.yaml          ← einmalig manuell angewendet
  └── bootstrap/app-of-apps.yaml (ApplicationSet)
        ├── local/               ← nur homelab-env: local (k3d)
        │     └── gitea/         ← lokaler Git-Server
        ├── infrastructure/      ← alle Cluster (MetalLB, Traefik, ...)
        ├── config/              ← CRD-abhängige Konfiguration
        │     └── system-upgrade/ ← nur homelab-env: production
        └── apps/                ← alle Cluster (Paperless, HA, ...)
```

ArgoCD liest `repoURL` und `targetRevision` aus dem Cluster-Secret
`argocd/homelab-cluster`. Damit wird derselbe ApplicationSet sowohl lokal
(Gitea-URL + Feature-Branch) als auch in Produktion (GitHub-URL + HEAD)
verwendet.

## Lizenz

[MIT](LICENSE)
