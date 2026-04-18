# Secrets-Management mit Sealed Secrets

## Konzept

Sealed Secrets verschlüsselt Kubernetes Secrets so, dass sie sicher in Git committet werden können. Nur der Sealed Secrets Controller im Cluster kann sie entschlüsseln.

## Workflow

### Secret erstellen und versiegeln

```bash
# 1. Secret als YAML generieren (ohne es anzuwenden)
kubectl create secret generic my-secret \
  --from-literal=username=admin \
  --from-literal=password=supersecret \
  --dry-run=client -o yaml -n my-namespace > /tmp/my-secret.yaml

# 2. Versiegeln (verschlüsseln)
kubeseal --format yaml < /tmp/my-secret.yaml > my-sealed-secret.yaml

# 3. Originales Secret LÖSCHEN (niemals committen!)
rm /tmp/my-secret.yaml

# 4. Versiegeltes Secret in Git committen ✅
git add my-sealed-secret.yaml
git commit -m "feat: add sealed secret for my-app"
```

### Secret aus Datei versiegeln

```bash
kubeseal --format yaml \
  --namespace my-namespace \
  --name my-secret \
  < /tmp/my-secret.yaml \
  > my-sealed-secret.yaml
```

### Controller-Key sichern (KRITISCH!)

**Sofort nach dem ersten Deploy ausführen und Backup sicher aufbewahren!**

```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > ~/sealed-secrets-master-key-BACKUP-$(date +%Y%m%d).yaml
```

Backup-Orte:
- Passwortmanager (z.B. Bitwarden, 1Password)
- Verschlüsselter USB-Stick
- NAS (anderes Verzeichnis als K8s-Daten)

**Ohne diesen Key können Sealed Secrets nach einem Cluster-Rebuild NICHT entschlüsselt werden!**

### Sealed Secret wiederherstellen

Bei neuem Cluster den alten Controller-Key einspielen:

```bash
kubectl apply -f ~/sealed-secrets-master-key-BACKUP-20260101.yaml
kubectl rollout restart deployment sealed-secrets -n kube-system
```

## Namespaces beachten

Sealed Secrets sind namespace-spezifisch! Ein Secret für `paperless` kann nicht in `home-assistant` verwendet werden.

```bash
# Namespace explizit angeben
kubectl create secret generic paperless-secrets \
  --from-literal=PAPERLESS_SECRET_KEY=... \
  --dry-run=client -o yaml -n paperless | \
  kubeseal --format yaml > apps/paperless-ngx/paperless-sealed-secret.yaml
```

## Benötigte Secrets pro App

### Paperless-ngx

```bash
kubectl create secret generic paperless-secrets \
  --from-literal=PAPERLESS_SECRET_KEY=$(openssl rand -base64 48) \
  --from-literal=PAPERLESS_ADMIN_USER=admin \
  --from-literal=PAPERLESS_ADMIN_PASSWORD=$(openssl rand -base64 16) \
  --dry-run=client -o yaml -n paperless | \
  kubeseal --format yaml > apps/paperless-ngx/paperless-sealed-secret.yaml
```

### Mosquitto Passwort-Datei

```bash
# Mosquitto passwd-Datei erstellen
docker run --rm eclipse-mosquitto mosquitto_passwd -c -b /tmp/passwd mqtt-user MQTT_PASSWORT
# Oder auf einem Linux-System: mosquitto_passwd -c /tmp/passwd mqtt-user

kubectl create secret generic mosquitto-passwd \
  --from-file=passwd=/tmp/passwd \
  --dry-run=client -o yaml -n home-assistant | \
  kubeseal --format yaml > apps/home-assistant/mosquitto/mosquitto-passwd-sealed.yaml
```

### Zigbee2MQTT (MQTT-Credentials)

```bash
kubectl create secret generic zigbee2mqtt-secrets \
  --from-literal=ZIGBEE2MQTT_CONFIG_MQTT_USER=mqtt-user \
  --from-literal=ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD=MQTT_PASSWORT \
  --dry-run=client -o yaml -n home-assistant | \
  kubeseal --format yaml > apps/home-assistant/zigbee2mqtt/zigbee2mqtt-sealed-secret.yaml
```
