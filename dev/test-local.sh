#!/usr/bin/env bash
# Smoke-Tests für das lokale k3d-Cluster
# Voraussetzung: ./dev/bootstrap-local.sh wurde erfolgreich ausgeführt

set -euo pipefail

CLUSTER_NAME="homelab"
PASS=0
FAIL=0

ok()   { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
section() { echo ""; echo "── $1 ──────────────────────────────────────"; }

# --- Cluster erreichbar? ---
section "Cluster"
if k3d cluster list 2>/dev/null | grep -q "^$CLUSTER_NAME"; then
  ok "k3d-Cluster '$CLUSTER_NAME' existiert"
else
  echo "FEHLER: Cluster '$CLUSTER_NAME' nicht gefunden. Erst ./dev/bootstrap-local.sh ausführen."
  exit 1
fi

NODES_READY=$(kubectl get nodes --no-headers 2>/dev/null \
  | awk '$2=="Ready" {count++} END {print count+0}')
NODES_TOTAL=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [ "$NODES_READY" -eq "$NODES_TOTAL" ] && [ "$NODES_TOTAL" -gt 0 ]; then
  ok "Nodes: $NODES_READY/$NODES_TOTAL Ready"
else
  fail "Nodes: $NODES_READY/$NODES_TOTAL Ready"
fi

# --- ArgoCD ---
section "ArgoCD"
ARGOCD_PODS=$(kubectl get pods -n argocd --no-headers 2>/dev/null \
  | awk '$3=="Running" {count++} END {print count+0}')
if [ "$ARGOCD_PODS" -gt 0 ]; then
  ok "ArgoCD: $ARGOCD_PODS Pods Running"
else
  fail "ArgoCD: keine Running Pods in Namespace argocd"
fi

APPS_TOTAL=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l | tr -d ' ')
APPS_SYNCED=$(kubectl get applications -n argocd --no-headers 2>/dev/null \
  | awk '$2=="Synced" {count++} END {print count+0}')
APPS_HEALTHY=$(kubectl get applications -n argocd --no-headers 2>/dev/null \
  | awk '$3=="Healthy" {count++} END {print count+0}')

if [ "$APPS_TOTAL" -gt 0 ]; then
  ok "ArgoCD Apps gefunden: $APPS_TOTAL"
  [ "$APPS_SYNCED" -eq "$APPS_TOTAL" ] \
    && ok "Alle Apps Synced ($APPS_SYNCED/$APPS_TOTAL)" \
    || fail "Apps Synced: $APPS_SYNCED/$APPS_TOTAL"
  [ "$APPS_HEALTHY" -eq "$APPS_TOTAL" ] \
    && ok "Alle Apps Healthy ($APPS_HEALTHY/$APPS_TOTAL)" \
    || fail "Apps Healthy: $APPS_HEALTHY/$APPS_TOTAL"
else
  fail "Keine ArgoCD Applications gefunden (root-app noch nicht angewendet?)"
fi

# --- MetalLB ---
section "MetalLB"
METALLB_CTRL=$(kubectl get pods -n metallb-system -l app=metallb,component=controller \
  --no-headers 2>/dev/null | awk '$3=="Running" {count++} END {print count+0}')
if [ "$METALLB_CTRL" -gt 0 ]; then
  ok "MetalLB Controller Running"
else
  fail "MetalLB Controller nicht Running"
fi

IP_POOL=$(kubectl get ipaddresspool -n metallb-system --no-headers 2>/dev/null | wc -l | tr -d ' ')
[ "$IP_POOL" -gt 0 ] && ok "MetalLB IPAddressPool konfiguriert" || fail "Kein IPAddressPool gefunden"

# --- Traefik ---
section "Traefik"
TRAEFIK_SVC_TYPE=$(kubectl get svc -n traefik traefik \
  -o jsonpath='{.spec.type}' 2>/dev/null || echo "")
TRAEFIK_IP=$(kubectl get svc -n traefik traefik \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ "$TRAEFIK_SVC_TYPE" = "LoadBalancer" ]; then
  ok "Traefik Service Type: LoadBalancer"
else
  fail "Traefik Service nicht gefunden oder kein LoadBalancer (Typ: '${TRAEFIK_SVC_TYPE:-nicht gefunden}')"
fi

if [ "${CI:-false}" = "true" ]; then
  ok "Traefik LoadBalancer-IP-Test übersprungen (CI=true, L2 Advertisement in GitHub Actions nicht verfügbar)"
elif [ -n "$TRAEFIK_IP" ]; then
  ok "Traefik hat LoadBalancer-IP: $TRAEFIK_IP"
else
  fail "Traefik hat keine LoadBalancer-IP (MetalLB noch nicht bereit?)"
fi

# --- Ergebnis ---
echo ""
echo "══════════════════════════════════════════"
TOTAL=$((PASS + FAIL))
echo "  Ergebnis: $PASS/$TOTAL Tests bestanden"
if [ "$FAIL" -eq 0 ]; then
  echo "  ✓ Alle Tests grün — Cluster bereit!"
else
  echo "  ✗ $FAIL Test(s) fehlgeschlagen"
fi
echo "══════════════════════════════════════════"
echo ""

[ "$FAIL" -eq 0 ]
