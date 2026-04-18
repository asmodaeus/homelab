# TLS-Setup (Phase 4)

Externe Erreichbarkeit mit Let's Encrypt-Zertifikaten via Cloudflare DNS-01.

## Voraussetzungen

- Domain registriert (z.B. yourdomain.com)
- Domain zu Cloudflare als DNS-Provider migriert (kostenlos)
- Cloudflare API-Token erstellt

## Cloudflare API-Token erstellen

1. Cloudflare Dashboard → My Profile → API Tokens → Create Token
2. Template: "Edit zone DNS"
3. Zone Resources: Include → Specific zone → yourdomain.com
4. Token sicher aufbewahren!

## cert-manager aktivieren

1. `infrastructure/cert-manager/cluster-issuer.yaml` anpassen:

```yaml
# E-Mail und Cloudflare-Credentials eintragen
email: deine@email.com
```

2. Cloudflare API-Token als Sealed Secret erstellen:

```bash
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=DEIN_CLOUDFLARE_TOKEN \
  --dry-run=client -o yaml -n cert-manager | \
  kubeseal --format yaml > infrastructure/cert-manager/cloudflare-token-sealed.yaml
```

3. Wildcard-Zertifikat-Resource erstellen:

```yaml
# infrastructure/cert-manager/wildcard-cert.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-home
  namespace: traefik
spec:
  secretName: wildcard-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - "*.home.yourdomain.com"  # ANPASSEN
    - "home.yourdomain.com"
```

## HTTPRoutes aktualisieren

Alle HTTPRoutes auf HTTPS und echte Hostnamen umstellen:

```yaml
# Vorher (Phase 1-3):
hostnames:
  - paperless.local

# Nachher (Phase 4):
hostnames:
  - paperless.home.yourdomain.com
```

Und Gateway-Listener für HTTPS verwenden:

```yaml
parentRefs:
  - name: homelab
    namespace: traefik
    sectionName: websecure  # statt "web"
```

## DNS-Records

Nach Zertifikats-Ausstellung DNS-Records setzen:

```
paperless.home.yourdomain.com   → 192.168.1.200 (MetalLB Traefik IP)
ha.home.yourdomain.com          → 192.168.1.200
grafana.home.yourdomain.com     → 192.168.1.200
zigbee.home.yourdomain.com      → 192.168.1.200
```

Für externen Zugriff: Cloudflare Tunnel oder Split-DNS empfohlen (kein Port-Forwarding!).
