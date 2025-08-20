#!/bin/bash
set -e

# EcoTrack Platform Cluster Setup Script
# This script sets up the k3d cluster and basic infrastructure

CLUSTER_NAME="ecotrack-platform"
KUBECONFIG_PATH="$HOME/.config/k3d/kubeconfig-${CLUSTER_NAME}.yaml"

echo "🏗️ Setting up EcoTrack k3d cluster..."

# Create k3d cluster
k3d cluster create "$CLUSTER_NAME" \
    --agents 2 \
    --port "80:80@loadbalancer" \
    --port "443:443@loadbalancer" \
    --k3s-arg "--disable=traefik@server:*" \
    --wait

# Configure kubeconfig
export KUBECONFIG="$KUBECONFIG_PATH"
k3d kubeconfig merge "$CLUSTER_NAME" --kubeconfig-switch-context

echo "✅ Cluster created successfully!"
echo "📝 KUBECONFIG set to: $KUBECONFIG_PATH"
echo ""
echo "🔗 To use the cluster:"
echo "export KUBECONFIG=$KUBECONFIG_PATH"