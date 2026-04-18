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

## RAM-Budget Pi 4 2GB

| Komponente | RAM (geschätzt) |
|---|---|
| K3s server + etcd | ~400MB |
| ArgoCD | ~400MB |
| Traefik | ~100MB |
| Sealed Secrets | ~50MB |
| Paperless-ngx + Deps | ~400MB |
| OS + System | ~150MB |
| **Summe Phase 1+2** | **~1500MB** |
| Victoria Metrics + Grafana (Phase 2) | +~300MB |
| **Summe mit Monitoring** | **~1800MB** |

Monitoring (Phase 2) erst aktivieren wenn 3. Pi (ehem. HA-Pi) im Cluster ist!

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

- **Router:** UniFi Dream Machine Pro
- **Subnetz:** 192.168.1.0/24
- **MetalLB Range:** 192.168.1.200–192.168.1.210 (aus DHCP-Pool ausgeschlossen)
- **Pi 4:** 192.168.1.10 (statische DHCP-Lease)
- **Pi 3:** 192.168.1.11 (statische DHCP-Lease)
- **NAS:** 192.168.1.20 (statische DHCP-Lease)
