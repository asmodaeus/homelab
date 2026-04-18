## Was wurde geändert

<!-- Kurze Beschreibung der Änderungen -->

## Warum

<!-- Motivation / Problem das gelöst wird -->

## Testing

- [ ] CI grün (yamllint, helm lint, kubeconform)
- [ ] Auf Cluster getestet (falls zutreffend)
- [ ] `argocd app sync` läuft ohne Fehler durch

## Checklist

- [ ] Secrets versiegelt – kein Plaintext in Git
- [ ] Resource Limits auf neuen Pods gesetzt
- [ ] ARM64-Kompatibilität der verwendeten Images geprüft
- [ ] Dokumentation aktualisiert (falls nötig)
