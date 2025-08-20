#!/bin/bash

# EcoTrack Platform Status Check Script

CLUSTER_NAME="ecotrack-platform"
export KUBECONFIG="$HOME/.config/k3d/kubeconfig-${CLUSTER_NAME}.yaml"

echo "🌱 EcoTrack Platform Status"
echo "==========================="
echo ""

# Check cluster status
echo "📦 Cluster Status:"
k3d cluster list | grep "$CLUSTER_NAME" || echo "❌ Cluster not found"
echo ""

# Check nodes
echo "🖥️ Node Status:"
kubectl get nodes -o wide
echo ""

# Check namespaces
echo "📂 Namespaces:"
kubectl get namespaces
echo ""

# Check platform services
echo "🏗️ Platform Services:"
echo ""

echo "🔗 MetalLB LoadBalancer:"
kubectl get pods -n metallb-system
echo ""

echo "🌐 NGINX Ingress:"
kubectl get pods -n ingress-nginx
echo ""

echo "🔐 Cert-Manager:"
kubectl get pods -n cert-manager
echo ""

echo "🕸️ Istio Service Mesh:"
kubectl get pods -n istio-system
echo ""

echo "🔄 ArgoCD:"
kubectl get pods -n argocd
echo ""

echo "📊 Monitoring Stack:"
kubectl get pods -n monitoring
echo ""

echo "🗄️ Data Services:"
kubectl get pods -n data-services
echo ""

echo "🎯 Applications:"
kubectl get pods -n ecotrack-dev
echo ""

# Check services
echo "🔗 LoadBalancer Services:"
kubectl get svc --all-namespaces -o wide | grep LoadBalancer
echo ""

# Check ingress
echo "🌐 Ingress Resources:"
kubectl get ingress --all-namespaces
echo ""

# Check certificates
echo "🔐 TLS Certificates:"
kubectl get certificates --all-namespaces
echo ""

echo "✅ Platform status check complete!"