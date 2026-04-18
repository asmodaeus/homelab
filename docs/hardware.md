# Hardware

## Cluster-Nodes

### Pi 4 Model B (2GB) – `pi4`

- **Rolle:** K3s Control Plane + Worker
- **CPU:** ARM Cortex-A72 (ARMv8), 1.5GHz, 4 Cores
- **RAM:** 2GB LPDDR4
- **OS:** Raspberry Pi OS Lite 64-bit (bookworm)
- **Storage:** SD-Karte (K3s + OS), NFS (persistente App-Daten)
- **Netzwerk:** Gigabit Ethernet (kabelgebunden!)
- **Workloads:** ArgoCD, Traefik, Sealed Secrets, Paperless-ngx, Home Assistant

### Pi 4 Model B (2GB) – `pi-ha` (nach HA-Migration)

- **Rolle:** K3s Agent (nach Migration des dedizierten HA-Pi)
- **CPU:** ARM Cortex-A72 (ARMv8), 1.5GHz, 4 Cores
- **RAM:** 2GB LPDDR4
- **OS:** Raspberry Pi OS Lite 64-bit (bookworm) – nach Migration neu aufsetzen
- **Netzwerk:** Gigabit Ethernet (kabelgebunden)
- **Workloads:** Home Assistant, Paperless-ngx oder Monitoring (entlastet `pi4`)

> Vor Migration: HA-Backup erstellen! Siehe [zigbee-migration.md](zigbee-migration.md)

### Pi 3 Model B V1.2 (1GB) – `pi3`

- **Rolle:** K3s Agent (nur leichte Workloads!)
- **CPU:** ARM Cortex-A53 (ARMv8), 1.2GHz, 4 Cores
- **RAM:** 1GB LPDDR2
- **OS:** Raspberry Pi OS Lite 64-bit (bookworm)
- **Storage:** SD-Karte, NFS (Zigbee2MQTT DB)
- **Netzwerk:** Fast Ethernet 100Mbit (kabelgebunden)
- **USB:** Zigbee USB-Adapter (z.B. ConBee II, Sonoff Zigbee 3.0)
- **Workloads:** Zigbee2MQTT, Mosquitto
- **Taints:** `workload=light:NoSchedule`, Label: `homelab/zigbee-adapter=true`

> **Wichtig:** Pi 3 hat nur 1GB RAM. K3s-Agent selbst belegt ~200MB, verbleiben ~800MB für Pods.
> Niemals schwere Workloads (Paperless, ArgoCD, Prometheus) auf Pi 3 deployen!

## RAM-Budget (Zielzustand nach Phase 3: 2x Pi 4 + Pi 3)

### `pi4` – Control Plane + Infrastruktur

| Komponente | RAM (geschätzt) |
|---|---|
| K3s server + etcd | ~400MB |
| ArgoCD (4 Pods) | ~400MB |
| Traefik | ~100MB |
| Sealed Secrets + NFS Prov. | ~100MB |
| System Upgrade Controller | ~50MB |
| OS + System | ~150MB |
| **Reserve** | **~800MB** |

### `pi-ha` – App-Worker (nach Migration)

| Komponente | RAM (geschätzt) |
|---|---|
| K3s agent | ~200MB |
| Home Assistant | ~300MB |
| Paperless-ngx + Deps | ~500MB |
| Victoria Metrics + Grafana (Phase 2) | ~300MB |
| OS + System | ~150MB |
| **Reserve** | **~550MB** |

### `pi3` – Zigbee-Node

| Komponente | RAM (geschätzt) |
|---|---|
| K3s agent | ~200MB |
| Zigbee2MQTT | ~128MB |
| Mosquitto | ~32MB |
| **Reserve** | **~640MB** |

> Mit 2x Pi 4 2GB ist das RAM-Budget deutlich entspannter. Monitoring (Phase 2) kann auf `pi-ha` laufen.

## Zigbee USB-Adapter

USB-Pfad auf Pi 3 ermitteln:

```bash
ssh pi@<pi3-ip>
ls -la /dev/ttyUSB* /dev/ttyACM*
# Oder nach dem Einstecken: dmesg | tail -20
```

Häufige Pfade:
- ConBee II: `/dev/ttyACM0`
- Sonoff Zigbee 3.0 Plus: `/dev/ttyUSB0`
- HUSBZB-1: `/dev/ttyUSB1` (Z-Wave), `/dev/ttyUSB0` (Zigbee)

Pfad in `apps/home-assistant/zigbee2mqtt/configmap.yaml` und `deployment.yaml` anpassen!

## SD-Karten Empfehlungen

Für K3s auf SD-Karte:
- **Mindestens:** Samsung PRO Endurance oder SanDisk MAX Endurance (hohe Schreibzyklen)
- **Alternativ:** USB-SSD (USB 3.0 am Pi 4) für etcd und K3s-Daten
- Kritische Daten (Paperless, HA) liegen auf NAS → SD-Karte-Ausfall unkritisch

## Netzwerk

- **Router:** Heimnetz-Router
- **Subnetz:** 192.168.1.0/24
- **MetalLB Range:** 192.168.1.200–192.168.1.210 (aus DHCP-Pool ausgeschlossen)
- **Pi 4 (`pi4`):** 192.168.1.10 (statische DHCP-Lease)
- **Pi 3 (`pi3`):** 192.168.1.11 (statische DHCP-Lease)
- **Pi 4 HA (`pi-ha`):** 192.168.1.12 (statische DHCP-Lease, nach Migration)
- **NAS:** 192.168.1.20 (statische DHCP-Lease)
