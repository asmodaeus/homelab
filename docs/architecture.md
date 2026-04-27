# Architektur

## Übersicht

```
Internet
    │
    │ (Phase 4: Cloudflare DNS + Tunnel)
    ▼
Router/Firewall
    │
    │ 192.168.1.0/24
    ├─────────────────────────────────────┐
    │                                     │
    ▼                                     ▼
Pi 4 (192.168.1.10)              Pi 3 (192.168.1.11)
K3s Control Plane + Worker       K3s Agent
────────────────────────         ────────────────────
ArgoCD                           Zigbee2MQTT
Traefik (MetalLB IP)             Mosquitto
Sealed Secrets
NFS Provisioner
Paperless-ngx
Home Assistant
    │                                     │
    └──────────────────┬──────────────────┘
                       │ NFS
                       ▼
                   NAS (192.168.1.20)
                   /volume1/k8s/
                   ├── paperless-*/
                   ├── home-assistant-*/
                   ├── mosquitto-*/
                   └── zigbee2mqtt-*/
```

## GitOps-Flow

```
Developer (git push)
        │
        ▼
    GitHub
    asmodaeus/homelab (main)
        │
        │ ArgoCD pollt alle 3min
        ▼
    ArgoCD (im Cluster)
        │
        ├── Sync Wave -3: MetalLB
        ├── Sync Wave -2: Traefik, Sealed Secrets, NFS, cert-manager
        ├── Sync Wave -1: System Upgrade Controller
        ├── Sync Wave  0: Paperless-ngx, Home Assistant Stack
        └── Sync Wave  1: Monitoring (Phase 2, nur mit Cluster-Label)
```

## Netzwerk-Flow für eingehende Anfragen

```
Browser (http://paperless.local)
        │
        ▼
MetalLB (192.168.1.200) ← LoadBalancer Service
        │
        ▼
Traefik (Gateway API)
        │
        │ HTTPRoute: paperless.local → paperless:8000
        ▼
Paperless-ngx Pod (Pi 4)
```

## Storage-Architektur

```
App PVC (ReadWriteOnce)
    │
    │ NFS Mount
    ▼
NFS Subdir External Provisioner
    │
    │ NFS Protocol
    ▼
NAS: /volume1/k8s/<namespace>-<pvc>-<uid>/
    │
    │ NAS-Backup
    ▼
Backblaze B2 (optional, via Synology Hyper Backup)
```

## Sync Waves (ArgoCD)

ArgoCD deployt Ressourcen in Wellen, um Abhängigkeiten zu respektieren:

| Wave | Komponenten | Grund |
|---|---|---|
| -3 | MetalLB | Muss vor Traefik laufen (LoadBalancer IPs) |
| -2 | Traefik, Sealed Secrets, NFS Provisioner, cert-manager | Infrastructure vor Apps |
| -1 | System Upgrade Controller | Nach Cluster-Infrastruktur |
| 0 | Paperless-ngx, Home Assistant Stack | App-Layer |
| 1 | Victoria Metrics, Grafana | Monitoring (Phase 2, nur bei `homelab-monitoring=enabled`) |

## Ressourcen-Budget

### Pi 4 (2GB RAM) – Ziel Phase 2

| Komponente | RAM | CPU |
|---|---|---|
| K3s server + etcd | ~400MB | ~5% |
| ArgoCD (4 Pods) | ~400MB | ~3% |
| Traefik | ~100MB | ~1% |
| Sealed Secrets | ~50MB | <1% |
| NFS Provisioner | ~50MB | <1% |
| Paperless-ngx | ~400MB | ~10% |
| Home Assistant | ~300MB | ~5% |
| **Reserve** | **~300MB** | **~74%** |

### Pi 3 (1GB RAM) – Ziel Phase 2

| Komponente | RAM | CPU |
|---|---|---|
| K3s agent | ~200MB | ~5% |
| Zigbee2MQTT | ~128MB | ~5% |
| Mosquitto | ~32MB | <1% |
| **Reserve** | **~640MB** | **~89%** |
