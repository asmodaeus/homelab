# Bootstrap-Anleitung

Schritt-für-Schritt vom leeren Repo zum laufenden Cluster.

## Voraussetzungen

### Hardware vorbereiten

1. **Alle Pis mit 64-bit OS flashen**
   - Raspberry Pi Imager → Raspberry Pi OS Lite (64-bit)
   - SSH aktivieren, SSH-Key hinterlegen
   - Hostname setzen: `pi4`, `pi3`

2. **Statische DHCP-Leases** im Router
   - Network → LAN → DHCP → Static Leases
   - Pi 4: z.B. 192.168.1.10
   - Pi 3: z.B. 192.168.1.11

3. **MetalLB IP-Range aus DHCP ausschließen**
   - Network → LAN → DHCP Range auf z.B. 192.168.1.1–192.168.1.199 begrenzen
   - MetalLB nutzt dann 192.168.1.200–192.168.1.210

4. **NAS NFS-Export konfigurieren** (Synology Beispiel)
   - Control Panel → Shared Folder → k8s erstellen
   - File Services → NFS → NFS aktivieren
   - k8s → Edit → NFS Permissions → Pi-IPs eintragen (Subnetz: 192.168.1.0/24)

### Lokale Tools installieren

```bash
# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# kubeseal
VERSION=$(curl -s https://api.github.com/repos/bitnami-labs/sealed-secrets/releases/latest | grep tag_name | cut -d '"' -f 4)
curl -OL "https://github.com/bitnami-labs/sealed-secrets/releases/download/${VERSION}/kubeseal-${VERSION#v}-linux-amd64.tar.gz"
tar xzf kubeseal-*.tar.gz && sudo mv kubeseal /usr/local/bin/

# Ansible
pip3 install ansible ansible-lint
```

## Phase 1: K3s + ArgoCD Bootstrap

### 1. Ansible-Dependencies installieren

```bash
cd ansible
ansible-galaxy install -r requirements.yaml
cd ..
```

### 2. Inventory konfigurieren

```bash
vim ansible/inventory/hosts.yaml
# Pi-IPs anpassen

vim ansible/inventory/group_vars/all.yaml
# k3s_token: auf starkes, zufälliges Token setzen
# openssl rand -base64 48
```

### 3. SSH-Verbindung testen

```bash
ansible all -i ansible/inventory/hosts.yaml -m ping
```

### 4. OS vorbereiten

```bash
ansible-playbook ansible/playbooks/os-prep.yaml
# Pis werden neu gestartet (cgroups-Aktivierung)
```

### 5. K3s installieren

```bash
ansible-playbook ansible/playbooks/k3s-install.yaml
# Erstellt kubeconfig im Repo-Root (in .gitignore!)
```

### 6. Cluster verifizieren

```bash
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes -o wide
# Erwartete Ausgabe: pi4 (Ready, control-plane), pi3 (Ready)
```

### 7. Node-Labels und Taints setzen

```bash
# Pi 3: Taint für leichte Workloads
kubectl label node pi3 workload=light
kubectl taint node pi3 workload=light:NoSchedule

# Pi 3: Zigbee-Adapter-Label (USB-Stick ist hier angesteckt)
kubectl label node pi3 homelab/zigbee-adapter=true

# Verifizieren
kubectl describe node pi3 | grep -A5 Taints
kubectl describe node pi3 | grep -A5 Labels
```

### 8. ArgoCD installieren

```bash
# Optional vorab:
cp local.env.example local.env
vim local.env   # NAS_IP und NAS_PATH setzen, wenn NFS direkt mit vorbereitet werden soll

ansible-playbook ansible/playbooks/argocd-bootstrap.yaml
```

### 9. ArgoCD initial-Passwort ermitteln

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
echo
```

### 10. Root-App anwenden (GitOps aktivieren!)

```bash
kubectl apply -f bootstrap/root-app.yaml
```

Ab jetzt verwaltet ArgoCD alle weiteren Ressourcen aus Git.

### 11. ArgoCD UI öffnen

```bash
# IP der ArgoCD LoadBalancer-IP ermitteln (über MetalLB)
kubectl -n argocd get svc argocd-server
# Im Browser: http://<IP> (oder via port-forward: kubectl -n argocd port-forward svc/argocd-server 8080:80)
```

---

## Phase 2: Sealed Secrets + NFS + Paperless

### Sealed Secrets Controller-Key sichern

**SOFORT nach dem ersten Deploy!**

```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > ~/sealed-secrets-master-key-BACKUP.yaml
# Diese Datei AUSSERHALB des Repos sichern (Passwortmanager, NAS, ...)!
```

### NFS-Provisioner konfigurieren

```bash
# NAS-IP und Pfad in local.env pflegen
cp local.env.example local.env
vim local.env

# Cluster-Secret mit NAS-Werten erneut anwenden
ansible-playbook ansible/playbooks/argocd-bootstrap.yaml

# StorageClass verifizieren
kubectl get storageclass
# nfs sollte als (default) angezeigt werden
```

### Paperless-Secrets erstellen und versiegeln

```bash
kubectl create secret generic paperless-secrets \
  --from-literal=PAPERLESS_SECRET_KEY=$(openssl rand -base64 48) \
  --from-literal=PAPERLESS_ADMIN_USER=admin \
  --from-literal=PAPERLESS_ADMIN_PASSWORD=$(openssl rand -base64 16) \
  --dry-run=client -o yaml -n paperless | \
  kubeseal --format yaml > apps/paperless-ngx/paperless-sealed-secret.yaml

git add apps/paperless-ngx/paperless-sealed-secret.yaml
git commit -m "feat: add paperless sealed secrets"
git push
```

---

## Phase 3: Home Assistant Migration

Siehe [zigbee-migration.md](zigbee-migration.md) für die detaillierte Migrationsprozedur.

---

## Fehlersuche

### ArgoCD App stuck in "Progressing"

```bash
kubectl -n argocd get applications
argocd app get <app-name>
argocd app sync <app-name> --force
```

### Pod startet nicht (Pi 3, RAM-Druck)

```bash
kubectl describe pod <pod-name> -n <namespace>
# Wenn OOMKilled: Memory-Limits erhöhen oder App auf Pi 4 verschieben
kubectl top nodes
kubectl top pods -A
```

### NFS-Mount schlägt fehl

```bash
# Auf Pi testen
showmount -e <NAS-IP>
mount -t nfs <NAS-IP>:/volume1/k8s /mnt/test
```
