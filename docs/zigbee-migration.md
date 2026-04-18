# Home Assistant Migration (HA-Pi → Cluster)

Anleitung zur Migration des bestehenden HA-Pi in den K3s-Cluster.

## Vorbereitung

### 1. Zigbee USB-Adapter identifizieren

Auf dem aktuellen HA-Pi:

```bash
ls -la /dev/ttyUSB* /dev/ttyACM*
# Oder: dmesg | grep -i usb | tail -20
```

Notiere den genauen Pfad (z.B. `/dev/ttyACM0` für ConBee II).

Gleichen Pfad in diesen Dateien anpassen (BEVOR du den Pi 3 in den Cluster aufnimmst):
- `apps/home-assistant/zigbee2mqtt/configmap.yaml` → `serial.port`
- `apps/home-assistant/zigbee2mqtt/deployment.yaml` → `hostPath.path` und `mountPath`

### 2. Home Assistant Backup erstellen

Auf dem HA-Pi oder im HA-UI:

```bash
# Option A: HA UI → Settings → System → Backups → Create Backup
# Option B: manuell auf dem Pi
ssh pi@<ha-pi-ip>
cd /home/pi
tar czf ha-backup-$(date +%Y%m%d).tar.gz homeassistant/
# Backup auf lokalen Rechner kopieren
scp pi@<ha-pi-ip>:~/ha-backup-*.tar.gz ~/
```

### 3. Secrets vorbereiten

Erstelle alle benötigten Sealed Secrets **bevor** du den alten HA-Pi abschaltest:

```bash
# Mosquitto Passwort-Datei
mosquitto_passwd -c /tmp/passwd mqtt-user
kubectl create secret generic mosquitto-passwd \
  --from-file=passwd=/tmp/passwd \
  --dry-run=client -o yaml -n home-assistant | \
  kubeseal --format yaml > apps/home-assistant/mosquitto/mosquitto-passwd-sealed.yaml

# Zigbee2MQTT MQTT-Credentials
kubectl create secret generic zigbee2mqtt-secrets \
  --from-literal=ZIGBEE2MQTT_CONFIG_MQTT_USER=mqtt-user \
  --from-literal=ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD=<DEIN_PASSWORT> \
  --dry-run=client -o yaml -n home-assistant | \
  kubeseal --format yaml > apps/home-assistant/zigbee2mqtt/zigbee2mqtt-sealed-secret.yaml

git add apps/home-assistant/
git commit -m "feat: add home-assistant sealed secrets"
git push
```

## Migration durchführen

> **Wartungsfenster:** Zigbee-Geräte sind während der Migration kurzzeitig offline.
> Am besten zu einer ruhigen Zeit (z.B. nachts) durchführen.

### Schritt 1: Zigbee USB-Adapter vom HA-Pi zum Pi 3 umstecken

```bash
# Pi 3 vor dem Einstecken prüfen
ssh pi@<pi3-ip>
ls /dev/ttyUSB* /dev/ttyACM*  # Sollte leer sein

# Adapter umstecken
# Danach auf Pi 3 prüfen:
ls /dev/ttyUSB* /dev/ttyACM*  # Sollte den Adapter zeigen
```

### Schritt 2: HA-Pi abschalten

```bash
ssh pi@<ha-pi-ip>
sudo shutdown -h now
```

### Schritt 3: HA-Backup in NFS-Volume einspielen

```bash
# NFS-Volume für Home Assistant mounten (temporär auf Pi 4)
kubectl run -it --rm debug \
  --image=busybox \
  --overrides='{"spec":{"volumes":[{"name":"ha","persistentVolumeClaim":{"claimName":"home-assistant-config"}}],"containers":[{"name":"debug","image":"busybox","volumeMounts":[{"name":"ha","mountPath":"/config"}]}]}}' \
  --namespace=home-assistant \
  -- sh

# Im Container: Backup-Dateien hochladen
# (Alternativ: kubectl cp für einzelne Dateien)
exit

# Backup via kubectl cp ins PVC kopieren
kubectl cp ~/ha-backup-20260418.tar.gz \
  home-assistant/home-assistant-0:/tmp/backup.tar.gz
```

### Schritt 4: ArgoCD Sync erzwingen

```bash
kubectl -n argocd app sync root
# ArgoCD deployt Mosquitto, Zigbee2MQTT, Home Assistant
```

### Schritt 5: Zigbee-Geräte verifizieren

1. Zigbee2MQTT Frontend öffnen: http://zigbee.local
2. Alle Geräte sollten erscheinen (ggf. kurze Wartezeit)
3. Home Assistant öffnen: http://homeassistant.local
4. MQTT-Integration prüfen: Settings → Integrations → MQTT
5. Automationen testen

### Schritt 6: Alten HA-Pi dekommissionieren oder in Cluster aufnehmen

**Option A: Dekommissionieren**
```bash
# SD-Karte formatieren, Pi 3B als Reserve aufbewahren
```

**Option B: Als 3. K3s-Agent aufnehmen (empfohlen wenn Pi 4+!)**
```bash
# inventory/hosts.yaml: pi-ha als weiteren agent hinzufügen
# ansible-playbook ansible/playbooks/k3s-install.yaml --limit pi-ha
# kubectl label node pi-ha kubernetes.io/arch=arm64
```

## Rollback

Falls die Migration fehlschlägt:

1. Zigbee USB-Adapter zurück zum alten HA-Pi stecken
2. Alten HA-Pi einschalten
3. Cluster-Apps löschen: `kubectl -n home-assistant delete deployment home-assistant zigbee2mqtt mosquitto`
4. Ursache debuggen, dann erneut versuchen
