#!/bin/bash

set -e

echo "🧪 Starting EcoTrack Platform Tests..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=0

# Helper functions
log_info() {
    echo -e "${GREEN}ℹ️  $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

test_passed() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_info "✅ $1"
}

test_failed() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_error "❌ $1"
}

# Test 1: Cluster connectivity
test_cluster_connectivity() {
    echo "🔍 Testing cluster connectivity..."
    
    if kubectl cluster-info &>/dev/null; then
        test_passed "Kubernetes cluster is reachable"
    else
        test_failed "Kubernetes cluster is not reachable"
        return 1
    fi
    
    # Test node readiness
    READY_NODES=$(kubectl get nodes --no-headers | grep -c Ready || echo 0)
    TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l)
    
    if [ "$READY_NODES" -eq "$TOTAL_NODES" ] && [ "$READY_NODES" -gt 0 ]; then
        test_passed "All nodes are ready ($READY_NODES/$TOTAL_NODES)"
    else
        test_failed "Not all nodes are ready ($READY_NODES/$TOTAL_NODES)"
    fi
}

# Test 2: Core infrastructure components
test_core_infrastructure() {
    echo "🏗️ Testing core infrastructure components..."
    
    # Test MetalLB
    if kubectl get deployment -n metallb-system controller &>/dev/null; then
        test_passed "MetalLB controller is deployed"
    else
        test_failed "MetalLB controller not found"
    fi
    
    # Test NGINX Ingress
    if kubectl get deployment -n ingress-nginx ingress-nginx-controller &>/dev/null; then
        test_passed "NGINX Ingress controller is deployed"
    else
        test_failed "NGINX Ingress controller not found"
    fi
    
    # Test Cert-Manager
    if kubectl get deployment -n cert-manager cert-manager &>/dev/null; then
        test_passed "Cert-Manager is deployed"
    else
        test_failed "Cert-Manager not found"
    fi
}

# Test 3: Service mesh components
test_service_mesh() {
    echo "🕸️ Testing service mesh components..."
    
    # Test Istio system pods
    local istio_pods=(
        "istiod"
        "istio-proxy"
    )
    
    for component in "${istio_pods[@]}"; do
        if kubectl get pods -n istio-system | grep -q "$component.*Running"; then
            test_passed "Istio component '$component' is running"
        else
            test_failed "Istio component '$component' is not running"
        fi
    done
    
    # Test Istio gateways
    if kubectl get gateway -A &>/dev/null; then
        local gateways=$(kubectl get gateway -A --no-headers | wc -l)
        if [ "$gateways" -gt 0 ]; then
            test_passed "Istio gateways are configured ($gateways found)"
        else
            test_failed "No Istio gateways found"
        fi
    else
        test_failed "Istio gateway CRDs not available"
    fi
}

# Test 4: Monitoring stack
test_monitoring() {
    echo "📊 Testing monitoring stack..."
    
    # Test Prometheus
    if kubectl get deployment -n monitoring monitoring-kube-prometheus-prometheus &>/dev/null; then
        test_passed "Prometheus is deployed"
    else
        test_failed "Prometheus deployment not found"
    fi
    
    # Test Grafana
    if kubectl get deployment -n monitoring monitoring-grafana &>/dev/null; then
        test_passed "Grafana is deployed"
    else
        test_failed "Grafana deployment not found"
    fi
    
    # Test AlertManager
    if kubectl get deployment -n monitoring monitoring-kube-prometheus-alertmanager &>/dev/null; then
        test_passed "AlertManager is deployed"
    else
        test_failed "AlertManager deployment not found"
    fi
    
    # Test Jaeger
    if kubectl get deployment -n istio-system jaeger &>/dev/null; then
        test_passed "Jaeger is deployed"
    else
        test_failed "Jaeger deployment not found"
    fi
    
    # Test Kiali
    if kubectl get deployment -n istio-system kiali &>/dev/null; then
        test_passed "Kiali is deployed"
    else
        test_failed "Kiali deployment not found"
    fi
}

# Test 5: Data services
test_data_services() {
    echo "🗄️ Testing data services..."
    
    # Test PostgreSQL
    if kubectl get statefulset -n data-services postgresql &>/dev/null; then
        test_passed "PostgreSQL is deployed"
        
        # Test PostgreSQL readiness
        local pg_ready=$(kubectl get pods -n data-services -l app=postgresql --no-headers | grep -c "Running" || echo 0)
        if [ "$pg_ready" -gt 0 ]; then
            test_passed "PostgreSQL pods are running"
        else
            test_failed "PostgreSQL pods are not running"
        fi
    else
        test_failed "PostgreSQL StatefulSet not found"
    fi
    
    # Test Redis
    if kubectl get deployment -n data-services redis-master &>/dev/null; then
        test_passed "Redis is deployed"
        
        # Test Redis readiness
        local redis_ready=$(kubectl get pods -n data-services -l app=redis --no-headers | grep -c "Running" || echo 0)
        if [ "$redis_ready" -gt 0 ]; then
            test_passed "Redis pods are running"
        else
            test_failed "Redis pods are not running"
        fi
    else
        test_failed "Redis deployment not found"
    fi
    
    # Test Kafka
    if kubectl get statefulset -n data-services kafka &>/dev/null; then
        test_passed "Kafka is deployed"
        
        # Test Kafka readiness
        local kafka_ready=$(kubectl get pods -n data-services -l app=kafka --no-headers | grep -c "Running" || echo 0)
        if [ "$kafka_ready" -gt 0 ]; then
            test_passed "Kafka pods are running"
        else
            test_failed "Kafka pods are not running"
        fi
    else
        test_failed "Kafka StatefulSet not found"
    fi
}

# Test 6: GitOps components
test_gitops() {
    echo "🔄 Testing GitOps components..."
    
    # Test ArgoCD
    if kubectl get deployment -n argocd argocd-server &>/dev/null; then
        test_passed "ArgoCD server is deployed"
    else
        test_failed "ArgoCD server not found"
    fi
    
    # Test ArgoCD applications
    if kubectl get applications -n argocd &>/dev/null; then
        local apps=$(kubectl get applications -n argocd --no-headers | wc -l)
        if [ "$apps" -gt 0 ]; then
            test_passed "ArgoCD applications are configured ($apps found)"
        else
            test_failed "No ArgoCD applications found"
        fi
    else
        test_failed "ArgoCD application CRDs not available"
    fi
}

# Test 7: Application endpoints
test_application_endpoints() {
    echo "🚀 Testing application endpoints..."
    
    # Test demo application
    if kubectl get deployment -n ecotrack-dev ecotrack-demo &>/dev/null; then
        test_passed "Demo application is deployed"
        
        # Test service availability
        if kubectl get service -n ecotrack-dev ecotrack-demo &>/dev/null; then
            test_passed "Demo application service is available"
        else
            test_failed "Demo application service not found"
        fi
        
        # Test ingress configuration
        if kubectl get ingress -n ecotrack-dev ecotrack-demo &>/dev/null; then
            test_passed "Demo application ingress is configured"
        else
            test_failed "Demo application ingress not found"
        fi
    else
        test_failed "Demo application not found"
    fi
}

# Test 8: Security and RBAC
test_security() {
    echo "🔒 Testing security and RBAC..."
    
    # Test service accounts
    local service_accounts=(
        "ecotrack-demo:ecotrack-dev"
        "prometheus:monitoring"
        "grafana:monitoring"
    )
    
    for sa in "${service_accounts[@]}"; do
        local name=$(echo "$sa" | cut -d':' -f1)
        local namespace=$(echo "$sa" | cut -d':' -f2)
        
        if kubectl get serviceaccount -n "$namespace" "$name" &>/dev/null; then
            test_passed "Service account '$name' exists in namespace '$namespace'"
        else
            test_failed "Service account '$name' not found in namespace '$namespace'"
        fi
    done
    
    # Test pod security policies
    local secure_pods=$(kubectl get pods -A -o json | jq -r '.items[] | select(.spec.securityContext.runAsNonRoot == true) | .metadata.name' | wc -l)
    if [ "$secure_pods" -gt 0 ]; then
        test_passed "Found $secure_pods pods with security context configured"
    else
        test_failed "No pods found with proper security context"
    fi
}

# Test 9: Performance and resource limits
test_performance() {
    echo "⚡ Testing performance and resource limits..."
    
    # Test resource limits
    local pods_with_limits=$(kubectl get pods -A -o json | jq -r '.items[] | select(.spec.containers[].resources.limits) | .metadata.name' | wc -l)
    if [ "$pods_with_limits" -gt 0 ]; then
        test_passed "Found $pods_with_limits pods with resource limits"
    else
        test_failed "No pods found with resource limits"
    fi
    
    # Test horizontal pod autoscalers
    if kubectl get hpa -A &>/dev/null; then
        local hpas=$(kubectl get hpa -A --no-headers | wc -l)
        if [ "$hpas" -gt 0 ]; then
            test_passed "Found $hpas horizontal pod autoscalers"
        else
            log_warn "No horizontal pod autoscalers found (optional)"
        fi
    fi
}

# Test 10: Network connectivity
test_network_connectivity() {
    echo "🌐 Testing network connectivity..."
    
    # Test LoadBalancer service
    local lb_services=$(kubectl get services -A --field-selector spec.type=LoadBalancer --no-headers | wc -l)
    if [ "$lb_services" -gt 0 ]; then
        test_passed "Found $lb_services LoadBalancer services"
    else
        test_failed "No LoadBalancer services found"
    fi
    
    # Test ingress controllers
    local ingress_controllers=$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --no-headers | grep -c "Running" || echo 0)
    if [ "$ingress_controllers" -gt 0 ]; then
        test_passed "Ingress controllers are running ($ingress_controllers instances)"
    else
        test_failed "No running ingress controllers found"
    fi
}

# Main execution
main() {
    echo "🌱 EcoTrack Platform Test Suite"
    echo "==============================="
    echo
    
    # Run all tests
    test_cluster_connectivity
    test_core_infrastructure
    test_service_mesh
    test_monitoring
    test_data_services
    test_gitops
    test_application_endpoints
    test_security
    test_performance
    test_network_connectivity
    
    # Summary
    echo
    echo "📊 Test Summary"
    echo "==============="
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo "Success Rate: $(( TESTS_PASSED * 100 / TOTAL_TESTS ))%"
    echo
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        log_info "🎉 All tests passed! Platform is healthy."
        exit 0
    else
        log_error "⚠️  $TESTS_FAILED tests failed. Please check the issues above."
        exit 1
    fi
}

# Run main function
main "$@"