#!/usr/bin/env bash
# Lokales K3d-Cluster für homelab-Entwicklung
#
# Voraussetzungen:
#   brew install k3d kubectl helm docker jq   (macOS)
#   oder entsprechende Linux-Pakete
#
# Nutzung:
#   ./dev/bootstrap-local.sh                    # HEAD von main
#   REVISION=my-feature-branch ./dev/bootstrap-local.sh
#
# Einschränkungen gegenüber echtem Cluster:
#   - Architektur: x86_64 statt ARM64
#   - NFS Storage: nicht verfügbar → local-path-provisioner als Fallback
#     (PVCs mit storageClass: nfs bleiben Pending ohne lokalen NFS-Server)
#   - MetalLB IPs: Docker-Subnetz statt echtes LAN
#     Direkter Zugriff via IP erfordert: sudo ip route add <subnet> via <gw>
#     Einfacher: kubectl port-forward (siehe Ausgabe am Ende)

set -euo pipefail

CLUSTER_NAME="homelab"
REVISION="${REVISION:-HEAD}"
REPO_URL="https://github.com/asmodaeus/homelab.git"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# --- Voraussetzungen prüfen ---
echo "→ Prüfe Voraussetzungen..."
missing=()
for cmd in k3d kubectl helm docker jq; do
  command -v "$cmd" &>/dev/null || missing+=("$cmd")
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "FEHLER: Folgende Tools fehlen: ${missing[*]}"
  echo "  macOS:  brew install ${missing[*]}"
  echo "  Linux:  siehe https://k3d.io/installation"
  exit 1
fi

# Cluster ggf. vorher bereinigen
if k3d cluster list | grep -q "^$CLUSTER_NAME"; then
  echo "→ Cluster '$CLUSTER_NAME' existiert bereits – überspringe Erstellung"
else
  echo "→ Erstelle k3d-Cluster '$CLUSTER_NAME'..."
  k3d cluster create --config "$SCRIPT_DIR/k3d-config.yaml"
fi

echo "→ Warte auf Node-Readiness..."
kubectl wait --for=condition=Ready node --all --timeout=120s

# --- ArgoCD installieren (nur beim ersten Mal; danach self-managed via GitOps) ---
helm repo add argo https://argoproj.github.io/argo-helm --force-update 2>/dev/null
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
if helm status argocd -n argocd &>/dev/null 2>&1; then
  echo "→ ArgoCD bereits installiert – überspringe Helm-Upgrade (self-managed)"
else
  echo "→ Installiere ArgoCD..."
  helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --version "7.7.16" \
    -f "$REPO_ROOT/bootstrap/argocd/values.yaml" \
    --set "global.image.tag=v2.13.3" \
    --wait --timeout 5m
fi

# --- Cluster-Secret für ApplicationSet setzen (trägt targetRevision) ---
# Dieses Secret wird nicht von ArgoCD verwaltet – selfHeal überschreibt es nicht.
echo "→ Setze Cluster-Secret (revision: $REVISION)..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: homelab-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    homelab-cluster: "true"
    homelab-env: local
  annotations:
    targetRevision: "$REVISION"
stringData:
  name: in-cluster
  server: https://kubernetes.default.svc
  config: '{"tlsClientConfig":{"insecure":false}}'
EOF

# --- Root-App anwenden (optional: branch/tag überschreiben) ---
echo "→ Wende root-app an (revision: $REVISION)..."
if [ "$REVISION" != "HEAD" ]; then
  sed "s|targetRevision: HEAD|targetRevision: $REVISION|" \
    "$REPO_ROOT/bootstrap/root-app.yaml" | kubectl apply -f -
else
  kubectl apply -f "$REPO_ROOT/bootstrap/root-app.yaml"
fi

# --- Warten bis MetalLB controller läuft ---
echo "→ Warte auf MetalLB (kann 2-3 Minuten dauern)..."
for i in $(seq 1 30); do
  if kubectl get deployment -n metallb-system controller &>/dev/null 2>&1; then
    kubectl wait --for=condition=Available deployment/controller \
      -n metallb-system --timeout=120s && break
  fi
  sleep 10
done

# --- Warten bis MetalLB CRDs registriert sind ---
echo "→ Warte auf MetalLB CRDs..."
for i in $(seq 1 30); do
  if kubectl get crd ipaddresspools.metallb.io &>/dev/null 2>&1; then
    break
  fi
  [ "$i" -eq 30 ] && echo "WARNUNG: MetalLB CRDs nach 5 Minuten noch nicht bereit" && break
  sleep 10
done

# --- MetalLB IP-Pool auf Docker-Subnetz patchen ---
DOCKER_SUBNET=$(docker network inspect "k3d-$CLUSTER_NAME" \
  2>/dev/null | jq -r '.[0].IPAM.Config[0].Subnet' || echo "172.18.0.0/16")
BASE=$(echo "$DOCKER_SUBNET" | cut -d. -f1-3)
METALLB_RANGE="${BASE}.200-${BASE}.210"

echo "→ Patche MetalLB IP-Pool: $METALLB_RANGE"
kubectl patch ipaddresspool homelab -n metallb-system \
  --type=merge -p "{\"spec\":{\"addresses\":[\"$METALLB_RANGE\"]}}" \
  2>/dev/null || kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: homelab
  namespace: metallb-system
spec:
  addresses:
    - $METALLB_RANGE
EOF

# --- Ergebnis ---
ARGOCD_PW=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "<noch nicht bereit>")

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           Lokales Homelab-Cluster ist bereit!                 ║"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║  ArgoCD Port-Forward:                                         ║"
echo "║    kubectl port-forward -n argocd svc/argocd-server 8080:80  ║"
echo "║    → http://localhost:8080                                    ║"
printf "║  Login: admin / %-47s║\n" "$ARGOCD_PW"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║  MetalLB IP-Range: $METALLB_RANGE"
echo "║  (Direktzugriff via IP: sudo ip route add $DOCKER_SUBNET via $BASE.1)"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║  NFS Storage: Pending ohne lokalen NFS-Server                 ║"
echo "║  Fallback:    kubectl patch storageclass nfs                  ║"
echo "║               -p '{\"metadata\":{\"annotations\":{            ║"
echo "║               \"storageclass.kubernetes.io/is-default-class\": ║"
echo "║               \"false\"}}}'                                    ║"
echo "║               → local-path bleibt dann Default               ║"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║  Teardown: ./dev/teardown-local.sh                            ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Tipp: REVISION=<branch> $0   → anderen Branch testen"
