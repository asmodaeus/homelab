#!/usr/bin/env bash
# Lokales K3d-Cluster für homelab-Entwicklung
#
# Voraussetzungen:
#   brew install k3d kubectl helm docker jq git   (macOS)
#
# Nutzung:
#   ./dev/bootstrap-local.sh                    # aktuellen Branch deployen
#   REVISION=my-feature-branch ./dev/bootstrap-local.sh
#
# Einschränkungen gegenüber echtem Cluster:
#   - Architektur: x86_64 statt ARM64
#   - NFS Storage: nicht verfügbar → local-path-provisioner als Fallback
#   - MetalLB IPs: Docker-Subnetz statt echtes LAN
#   - k3s-Upgrade-Plans werden nicht deployed (homelab-env=local)

set -euo pipefail

# --- Lokale Konfiguration laden (nicht in CI) ---
NAS_IP=""
NAS_PATH=""
if [ "${CI:-false}" != "true" ]; then
	LOCAL_ENV="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/local.env"
	if [ -f "$LOCAL_ENV" ]; then
		# shellcheck source=/dev/null
		source "$LOCAL_ENV"
	else
		echo "HINWEIS: Keine local.env gefunden – NAS-Storage nicht verfügbar."
		echo "  cp local.env.example local.env && vim local.env"
	fi
	NAS_IP="${NAS_IP:-}"
	NAS_PATH="${NAS_PATH:-}"
fi

CLUSTER_NAME="homelab"
CURRENT_BRANCH=$(git -C "$(dirname "$0")/.." rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
REVISION="${REVISION:-$CURRENT_BRANCH}"
GITHUB_URL="https://github.com/asmodaeus/homelab.git"
ARGOCD_CHART_VERSION="7.7.17"
ARGOCD_IMAGE_TAG="v2.13.3"
GITEA_USER="gitea"
GITEA_PASS="gitea"
GITEA_REPO="homelab"
GITEA_LOCAL_URL="http://localhost:3000"
GITEA_CLUSTER_URL="http://gitea-http.gitea.svc:3000"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

cleanup() {
	if [ -n "${PF_PID:-}" ]; then
		kill "$PF_PID" 2>/dev/null || true
	fi
}

# --- Voraussetzungen prüfen ---
echo "→ Prüfe Voraussetzungen..."
missing=()
for cmd in k3d kubectl helm docker jq git; do
	command -v "$cmd" &>/dev/null || missing+=("$cmd")
done
if [ ${#missing[@]} -gt 0 ]; then
	echo "FEHLER: Folgende Tools fehlen: ${missing[*]}"
	echo "  macOS:  brew install ${missing[*]}"
	exit 1
fi

# --- Cluster erstellen ---
if k3d cluster list | grep -q "^$CLUSTER_NAME"; then
	echo "→ Cluster '$CLUSTER_NAME' existiert bereits – überspringe Erstellung"
else
	echo "→ Erstelle k3d-Cluster '$CLUSTER_NAME'..."
	k3d cluster create --config "$SCRIPT_DIR/k3d-config.yaml"
fi

echo "→ Warte auf Node-Readiness..."
kubectl wait --for=condition=Ready node --all --timeout=120s

if [ "${CI:-false}" != "true" ]; then
	# --- Gitea installieren ---
	helm repo add gitea https://dl.gitea.com/charts/ --force-update 2>/dev/null
	kubectl create namespace gitea --dry-run=client -o yaml | kubectl apply -f -
	if helm status gitea -n gitea &>/dev/null 2>&1; then
		echo "→ Gitea bereits installiert – überspringe"
	else
		echo "→ Installiere Gitea (lokaler Git-Server)..."
		helm upgrade --install gitea gitea/gitea \
			--namespace gitea \
			--version "10.6.0" \
			--set "gitea.admin.username=$GITEA_USER" \
			--set "gitea.admin.password=$GITEA_PASS" \
			--set "gitea.admin.email=gitea@local.dev" \
			--set "gitea.config.database.DB_TYPE=sqlite3" \
			--set "gitea.config.session.PROVIDER=memory" \
			--set "gitea.config.cache.ADAPTER=memory" \
			--set "gitea.config.queue.TYPE=level" \
			--set "service.http.type=LoadBalancer" \
			--set "service.http.port=3000" \
			--set "persistence.enabled=true" \
			--set "persistence.storageClass=local-path" \
			--set "persistence.size=1Gi" \
			--set "resources.requests.cpu=50m" \
			--set "resources.requests.memory=128Mi" \
			--set "resources.limits.memory=256Mi" \
			--set "redis-cluster.enabled=false" \
			--set "postgresql.enabled=false" \
			--set "postgresql-ha.enabled=false" \
			--wait --timeout 5m
	fi

	# --- Gitea per port-forward erreichbar machen (MetalLB noch nicht bereit) ---
	echo "→ Starte port-forward für Gitea (MetalLB noch nicht aktiv)..."
	kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=gitea -n gitea --timeout=120s
	kubectl port-forward -n gitea svc/gitea-http 3000:3000 &>/dev/null &
	PF_PID=$!
	trap cleanup EXIT

	echo "→ Warte bis Gitea auf localhost:3000 erreichbar ist..."
	for i in $(seq 1 30); do
		if curl -sf "$GITEA_LOCAL_URL/api/v1/version" &>/dev/null; then
			break
		fi
		[ "$i" -eq 30 ] && echo "FEHLER: Gitea nicht erreichbar nach 5 Minuten" && exit 1
		sleep 10
	done

	# --- Gitea-Repo anlegen und Branch pushen ---
	echo "→ Richte Gitea-Repo ein (revision: $REVISION)..."
	curl -sf -X POST "$GITEA_LOCAL_URL/api/v1/user/repos" \
		-u "$GITEA_USER:$GITEA_PASS" \
		-H "Content-Type: application/json" \
		-d "{\"name\":\"$GITEA_REPO\",\"auto_init\":false,\"private\":false}" \
		>/dev/null 2>&1 || true # ignorieren falls Repo bereits existiert

	GITEA_REMOTE="http://$GITEA_USER:$GITEA_PASS@localhost:3000/$GITEA_USER/$GITEA_REPO.git"
	git -C "$REPO_ROOT" remote add local "$GITEA_REMOTE" 2>/dev/null ||
		git -C "$REPO_ROOT" remote set-url local "$GITEA_REMOTE"

	echo "→ Pushe Branch '$REVISION' nach Gitea..."
	git -C "$REPO_ROOT" push local "HEAD:refs/heads/$REVISION" --force
fi

# --- ArgoCD installieren (nur beim ersten Mal; danach self-managed via GitOps) ---
helm repo add argo https://argoproj.github.io/argo-helm --force-update 2>/dev/null
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
if helm status argocd -n argocd &>/dev/null 2>&1; then
	echo "→ ArgoCD bereits installiert – überspringe (self-managed)"
else
	echo "→ Installiere ArgoCD..."
	helm upgrade --install argocd argo/argo-cd \
		--namespace argocd \
		--version "$ARGOCD_CHART_VERSION" \
		-f "$REPO_ROOT/bootstrap/argocd/values.yaml" \
		--set "global.image.tag=$ARGOCD_IMAGE_TAG" \
		--wait --timeout 5m
fi

# --- Cluster-Secret setzen (repoURL + targetRevision + nasIP + homelab-env=local) ---
# Nicht von ArgoCD verwaltet – selfHeal überschreibt es nicht.
# In CI: repoURL zeigt direkt auf GitHub (kein Gitea verfügbar)
if [ "${CI:-false}" = "true" ]; then
	REPO_URL="$GITHUB_URL"
	echo "→ Setze Cluster-Secret (revision: $REVISION, repo: GitHub)..."
else
	REPO_URL="$GITEA_CLUSTER_URL/$GITEA_USER/$GITEA_REPO.git"
	echo "→ Setze Cluster-Secret (revision: $REVISION, repo: Gitea)..."
fi
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
    repoURL: "$REPO_URL"
    nasIP: "$NAS_IP"
    nasPath: "$NAS_PATH"
stringData:
  name: in-cluster
  server: https://kubernetes.default.svc
  config: '{"tlsClientConfig":{"insecure":false}}'
EOF

# --- Root-App anwenden ---
if [ "${CI:-false}" = "true" ]; then
	# In CI: repoURL bleibt GitHub (bereits korrekt in root-app.yaml), nur Branch patchen
	echo "→ Wende root-app an (repo: GitHub, revision: $REVISION)..."
	sed \
		-e "s|targetRevision: HEAD|targetRevision: $REVISION|" \
		"$REPO_ROOT/bootstrap/root-app.yaml" | kubectl apply -f -
else
	echo "→ Wende root-app an (repo: Gitea, revision: $REVISION)..."
	sed \
		-e "s|repoURL: https://github.com/asmodaeus/homelab.git|repoURL: $GITEA_CLUSTER_URL/$GITEA_USER/$GITEA_REPO.git|" \
		-e "s|targetRevision: HEAD|targetRevision: $REVISION|" \
		"$REPO_ROOT/bootstrap/root-app.yaml" | kubectl apply -f -
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
if [ "${CI:-false}" = "true" ]; then
	echo "╔════════════════════════════════════════════════════════════════════╗"
	echo "║           CI-Cluster bootstrap abgeschlossen!                      ║"
	echo "╠════════════════════════════════════════════════════════════════════╣"
	printf "║  Revision: %-57s║\n" "$REVISION"
	printf "║  Repo:     %-57s║\n" "$GITHUB_URL"
	echo "╚════════════════════════════════════════════════════════════════════╝"
else
	echo "╔════════════════════════════════════════════════════════════════════╗"
	echo "║           Lokales Homelab-Cluster ist bereit!                      ║"
	echo "╠════════════════════════════════════════════════════════════════════╣"
	echo "║  Gitea (lokaler Git-Server):                                       ║"
	echo "║    http://localhost:3000                                           ║"
	printf "║    Login: %-58s║\n" "$GITEA_USER / $GITEA_PASS"
	echo "║    Remote: git push local                                          ║"
	echo "╠════════════════════════════════════════════════════════════════════╣"
	echo "║  ArgoCD:                                                           ║"
	echo "║    kubectl port-forward -n argocd svc/argocd-server 8080:80       ║"
	echo "║    → http://localhost:8080                                         ║"
	printf "║    Login: admin / %-50s║\n" "$ARGOCD_PW"
	echo "╠════════════════════════════════════════════════════════════════════╣"
	echo "║  Development Loop:                                                 ║"
	echo "║    git add -A && git commit -m 'my change'                        ║"
	echo "║    git push local   ← ArgoCD synct in ~30s                        ║"
	echo "╠════════════════════════════════════════════════════════════════════╣"
	echo "║  Teardown: ./dev/teardown-local.sh                                 ║"
	echo "╚════════════════════════════════════════════════════════════════════╝"
	echo ""
	echo "Tipp: REVISION=<branch> $0   → anderen Branch testen"
fi
