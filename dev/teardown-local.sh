#!/usr/bin/env bash
# Lokales K3d-Cluster vollständig entfernen

set -euo pipefail

CLUSTER_NAME="homelab"

if ! k3d cluster list 2>/dev/null | grep -q "^$CLUSTER_NAME"; then
	echo "Cluster '$CLUSTER_NAME' existiert nicht – nichts zu tun."
	exit 0
fi

echo "→ Lösche k3d-Cluster '$CLUSTER_NAME'..."
k3d cluster delete "$CLUSTER_NAME"
echo "✓ Cluster entfernt."
