# /argocd-status — ArgoCD App-Status anzeigen

Zeige den Status aller ArgoCD Applications im lokalen k3d-Cluster.

## Schritte

1. Prüfe ob der k3d-Cluster läuft:
   ```bash
   k3d cluster list
   ```
   Falls kein Cluster namens `homelab` läuft: Hinweis ausgeben und abbrechen.

2. Zeige alle ArgoCD Applications:
   ```bash
   kubectl get applications -n argocd \
     -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,MESSAGE:.status.conditions[0].message'
   ```

3. Falls Apps nicht Synced oder nicht Healthy sind: zeige Details mit
   ```bash
   kubectl describe application <name> -n argocd
   ```
   für jede betroffene App.

4. Zeige außerdem Node-Status:
   ```bash
   kubectl get nodes -o wide
   ```

Fasse am Ende zusammen: wie viele Apps Synced/Healthy, welche haben Probleme.
