# /new-app — Neue App-Boilerplate anlegen

Erstelle die komplette Verzeichnisstruktur für eine neue App unter `apps/`.

Der App-Name wird als Argument übergeben: `/new-app <name>`
Beispiel: `/new-app paperless-ngx`

## Konventionen (aus CLAUDE.md und bestehenden Apps übernehmen)

- Namespace = App-Name
- StorageClass: `nfs` (Retain-Policy, Daten auf NAS)
- Ingress: Traefik HTTPRoute (Gateway API), kein klassischer Ingress
- Sync Wave: `0` (Apps laufen nach Infrastruktur)
- Versionen immer explizit pinnen, kein `latest`
- Resource Limits auf allen Workloads
- Keine Plaintext-Secrets — Kommentar mit kubeseal-Hinweis einfügen

## Anzulegende Dateien

Erstelle folgende Dateien unter `apps/<name>/`:

1. `namespace.yaml` — Kubernetes Namespace
2. `helmrelease.yaml` — ArgoCD Application (Helm-Chart), mit Platzhaltern für Chart-URL und Version
3. `pvc.yaml` — PersistentVolumeClaim (storageClass: nfs)
4. `httproute.yaml` — Traefik HTTPRoute mit Platzhalter-Hostname

Orientiere dich an `apps/paperless-ngx/` als Referenz für Struktur und Annotationen.

Frage nach dem App-Namen falls kein Argument übergeben wurde.
Zeige am Ende welche Dateien angelegt wurden und welche Platzhalter noch angepasst werden müssen.
