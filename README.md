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
| Updates | [Renovate](https://docs.renovatebot.com/) + [System Upgrade Controller](https://github.com/rancher/system-upgrade-controller) |
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

## Bootstrap

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

# 6. ArgoCD bootstrappen
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

## Secrets verwalten

```bash
# Secret erstellen und versiegeln
kubectl create secret generic my-secret \
  --from-literal=key=value \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > sealed-secret.yaml

# Dann: sealed-secret.yaml in Git committen, original NICHT!
```

## Lizenz

[MIT](LICENSE)
