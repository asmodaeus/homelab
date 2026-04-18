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

- **Paperless-ngx** – Dokumentenmanagement (NFS Storage)
- **Home Assistant** – Heimautomatisierung
- **Zigbee2MQTT** – Zigbee Bridge (nodeSelector: `homelab/zigbee-adapter=true` → Pi 3)
- **Mosquitto** – MQTT Broker (läuft auf Pi 3 mit Zigbee2MQTT)

## Konventionen

- **Niemals** Plaintext-Secrets in Git → immer `kubeseal` verwenden
- Alle Änderungen via PR (nicht direkt auf `main`)
- Versionen immer explizit pinnen (kein `latest`-Tag)
- Resource Limits auf allen Workloads setzen
- ARM64-Kompatibilität vor neuen Images prüfen (`docker manifest inspect <image>`)
- Pi 3 hat nur 1GB RAM – keine schweren Workloads ohne Toleration für `workload=light`

## Wichtige Dateien

| Datei | Bedeutung |
|---|---|
| `bootstrap/root-app.yaml` | Einzige manuell angewendete Ressource – Schlüsselstein des GitOps-Systems |
| `ansible/inventory/hosts.yaml` | Pi-IPs und Rollen (muss vor Bootstrap ausgefüllt sein) |
| `infrastructure/metallb/ip-address-pool.yaml` | MetalLB IP-Range (im Router-DHCP ausschließen!) |
| `infrastructure/nfs-provisioner/values.yaml` | NAS-IP + NFS-Pfad (vor Phase 2 ausfüllen) |
| `apps/home-assistant/zigbee2mqtt/deployment.yaml` | USB-Device-Path (muss mit `ls /dev/ttyUSB* /dev/ttyACM*` geprüft werden) |

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
