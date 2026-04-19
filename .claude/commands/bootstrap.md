# /bootstrap — Lokales k3d-Cluster starten

Starte das lokale k3d-Entwicklungscluster und prüfe den Status.

## Schritte

1. Prüfe Voraussetzungen:
   ```bash
   for cmd in k3d kubectl helm docker jq; do command -v "$cmd" || echo "FEHLT: $cmd"; done
   ```
   Falls Tools fehlen: Installation erklären und abbrechen.

2. Prüfe ob der Cluster bereits läuft:
   ```bash
   k3d cluster list
   ```

3. Falls kein Cluster namens `homelab` existiert: Bootstrap ausführen:
   ```bash
   ./dev/bootstrap-local.sh
   ```
   Optionaler Branch: `REVISION=<branch> ./dev/bootstrap-local.sh`

4. Falls Cluster bereits läuft: nur Status anzeigen:
   ```bash
   kubectl get nodes -o wide
   kubectl get applications -n argocd
   ```

5. Zeige ArgoCD-Zugriff:
   - Port-Forward-Befehl ausgeben
   - Admin-Passwort ausgeben:
     ```bash
     kubectl -n argocd get secret argocd-initial-admin-secret \
       -o jsonpath='{.data.password}' | base64 -d
     ```

Falls ein anderer Branch getestet werden soll, kann das Argument übergeben werden:
`/bootstrap feat/mein-feature`
