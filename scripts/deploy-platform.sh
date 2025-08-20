#!/bin/bash
set -e

# EcoTrack Platform Deployment Script
# This script deploys the complete EcoTrack platform on k3d

echo "🌱 EcoTrack Platform Deployment"
echo "==============================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="ecotrack-platform"
LOAD_BALANCER_IP="172.18.255.200"
KUBECONFIG_PATH="$HOME/.config/k3d/kubeconfig-${CLUSTER_NAME}.yaml"

# Functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    commands=("docker" "kubectl" "helm" "k3d")
    for cmd in "${commands[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd is not installed. Please install it first."
            exit 1
        fi
    done
    
    log_success "All prerequisites are installed"
}

cleanup_existing_cluster() {
    log_info "Checking for existing cluster..."
    if k3d cluster list | grep -q "$CLUSTER_NAME"; then
        log_warning "Existing cluster found. Deleting..."
        k3d cluster delete "$CLUSTER_NAME" || true
        sleep 10
    fi
}

create_k3d_cluster() {
    log_info "Creating k3d cluster: $CLUSTER_NAME"
    
    k3d cluster create "$CLUSTER_NAME" \
        --agents 2 \
        --port "80:80@loadbalancer" \
        --port "443:443@loadbalancer" \
        --k3s-arg "--disable=traefik@server:*" \
        --wait
    
    # Set kubeconfig
    export KUBECONFIG="$KUBECONFIG_PATH"
    k3d kubeconfig merge "$CLUSTER_NAME" --kubeconfig-switch-context
    
    log_success "k3d cluster created successfully"
}

add_helm_repositories() {
    log_info "Adding Helm repositories..."
    
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo add jetstack https://charts.jetstack.io
    helm repo add metallb https://metallb.github.io/metallb
    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo add istio https://istio-release.storage.googleapis.com/charts
    
    helm repo update
    
    log_success "Helm repositories added and updated"
}

install_metallb() {
    log_info "Installing MetalLB..."
    
    kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f -
    
    helm install metallb metallb/metallb \
        -n metallb-system \
        --wait --timeout=5m
    
    # Configure IP pool
    sleep 30
    cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - ${LOAD_BALANCER_IP}-172.18.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: example
  namespace: metallb-system
spec:
  ipAddressPools:
  - first-pool
EOF
    
    log_success "MetalLB installed and configured"
}

install_cert_manager() {
    log_info "Installing Cert-Manager..."
    
    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
    
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --version v1.16.2 \
        --set crds.enabled=true \
        --wait --timeout=5m
    
    # Create cluster issuers
    sleep 30
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ecotrack-ca-cert
  namespace: cert-manager
spec:
  isCA: true
  commonName: ecotrack-ca
  secretName: ecotrack-ca-secret
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
    group: cert-manager.io
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ecotrack-ca-issuer
spec:
  ca:
    secretName: ecotrack-ca-secret
EOF
    
    log_success "Cert-Manager installed with CA issuer"
}

install_nginx_ingress() {
    log_info "Installing NGINX Ingress..."
    
    kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
    
    helm install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --set controller.service.type=LoadBalancer \
        --wait --timeout=5m
    
    log_success "NGINX Ingress installed"
}

install_istio() {
    log_info "Installing Istio service mesh..."
    
    # Install Istio base
    helm install istio-base istio/base \
        -n istio-system \
        --create-namespace \
        --wait
    
    # Install Istiod
    helm install istiod istio/istiod \
        -n istio-system \
        --wait --timeout=10m
    
    # Install Istio Gateway
    helm install istio-gateway istio/gateway \
        -n istio-system \
        --wait
    
    log_success "Istio service mesh installed"
}

install_argocd() {
    log_info "Installing ArgoCD..."
    
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    
    helm install argocd argo/argo-cd \
        -n argocd \
        --wait --timeout=5m
    
    log_success "ArgoCD installed"
}

install_monitoring() {
    log_info "Installing monitoring stack..."
    
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    # Create monitoring values
    cat <<EOF > /tmp/monitoring-values.yaml
prometheus:
  prometheusSpec:
    retention: 7d
    resources:
      requests:
        memory: 512Mi
        cpu: 100m
      limits:
        memory: 1Gi
        cpu: 500m
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi

grafana:
  adminPassword: "ecotrack-admin"
  resources:
    requests:
      memory: 128Mi
      cpu: 50m
    limits:
      memory: 256Mi
      cpu: 200m
  persistence:
    enabled: true
    size: 2Gi

alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        memory: 64Mi
        cpu: 50m
      limits:
        memory: 128Mi
        cpu: 100m

nodeExporter:
  enabled: true

kubeStateMetrics:
  enabled: true
EOF
    
    helm install monitoring prometheus-community/kube-prometheus-stack \
        -n monitoring \
        -f /tmp/monitoring-values.yaml \
        --wait --timeout=10m
    
    log_success "Monitoring stack installed"
}

install_data_services() {
    log_info "Installing data services..."
    
    kubectl create namespace data-services --dry-run=client -o yaml | kubectl apply -f -
    
    # PostgreSQL
    helm install postgresql bitnami/postgresql \
        -n data-services \
        --set auth.postgresPassword=ecotrack-postgres \
        --set auth.database=ecotrack \
        --set primary.persistence.size=5Gi \
        --wait --timeout=5m
    
    # Redis
    helm install redis bitnami/redis \
        -n data-services \
        --set auth.password=ecotrack-redis \
        --set master.persistence.size=2Gi \
        --set replica.replicaCount=1 \
        --wait --timeout=5m
    
    # Kafka
    helm install kafka bitnami/kafka \
        -n data-services \
        --set controller.replicaCount=1 \
        --set broker.replicaCount=1 \
        --set zookeeper.replicaCount=1 \
        --set broker.persistence.size=3Gi \
        --wait --timeout=8m
    
    log_success "Data services installed"
}

deploy_demo_application() {
    log_info "Deploying demo application..."
    
    kubectl create namespace ecotrack-dev --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace ecotrack-dev istio-injection=enabled --overwrite
    
    # Apply demo application manifests
    kubectl apply -f platform/applications/demo-app/
    
    log_success "Demo application deployed"
}

configure_ingress_rules() {
    log_info "Configuring ingress rules..."
    
    # Apply ingress configurations
    kubectl apply -f platform/ingress/
    
    log_success "Ingress rules configured"
}

print_access_information() {
    echo ""
    echo "🎉 EcoTrack Platform Deployment Complete!"
    echo "=========================================="
    echo ""
    echo "📋 Platform Summary:"
    echo "  ✅ k3d cluster with MetalLB LoadBalancer"
    echo "  ✅ NGINX Ingress with TLS certificates"
    echo "  ✅ Istio service mesh"
    echo "  ✅ ArgoCD for GitOps"
    echo "  ✅ Prometheus + Grafana monitoring"
    echo "  ✅ PostgreSQL + Redis + Kafka data services"
    echo "  ✅ Demo application with ingress"
    echo ""
    echo "🌍 Setup Local DNS:"
    echo "echo \"${LOAD_BALANCER_IP} demo.ecotrack.local grafana.ecotrack.local kiali.ecotrack.local jaeger.ecotrack.local argocd.ecotrack.local\" >> /etc/hosts"
    echo ""
    echo "🔗 Service Access:"
    echo "  • Demo App: https://demo.ecotrack.local"
    echo "  • Grafana: kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80"
    echo "  • Prometheus: kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090"
    echo "  • ArgoCD: kubectl port-forward -n argocd svc/argocd-server 8080:80"
    echo ""
    echo "🔑 Default Credentials:"
    echo "  • Grafana: admin / ecotrack-admin"
    echo "  • PostgreSQL: postgres / ecotrack-postgres"
    echo "  • Redis: default / ecotrack-redis"
    echo "  • ArgoCD admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
    echo ""
    echo "📖 Next Steps:"
    echo "  1. Add DNS entries to /etc/hosts"
    echo "  2. Access the demo application"
    echo "  3. Explore monitoring dashboards"
    echo "  4. Deploy your microservices using ArgoCD"
    echo ""
    echo "🚀 Happy coding with EcoTrack Platform!"
    echo ""
}

# Main execution
main() {
    echo "Starting EcoTrack Platform deployment..."
    echo "This will take approximately 10-15 minutes."
    echo ""
    
    check_prerequisites
    cleanup_existing_cluster
    create_k3d_cluster
    add_helm_repositories
    install_metallb
    install_cert_manager
    install_nginx_ingress
    install_istio
    install_argocd
    install_monitoring
    install_data_services
    deploy_demo_application
    configure_ingress_rules
    print_access_information
}

# Run main function
main "$@"