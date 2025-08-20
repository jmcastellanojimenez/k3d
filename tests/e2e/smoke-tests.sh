#!/bin/bash

set -e

# Configuration
ENVIRONMENT=${1:-"dev"}
NAMESPACE="ecotrack-${ENVIRONMENT}"
TIMEOUT=60

echo "💨 Starting EcoTrack Smoke Tests for environment: $ENVIRONMENT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

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
    log_info "✅ $1"
}

test_failed() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_error "❌ $1"
}

# Wait for service to be ready
wait_for_service() {
    local service=$1
    local port=$2
    local namespace=$3
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for service $service:$port in namespace $namespace..."
    
    while [ $attempt -le $max_attempts ]; do
        if kubectl get svc -n "$namespace" "$service" &>/dev/null; then
            local cluster_ip=$(kubectl get svc -n "$namespace" "$service" -o jsonpath='{.spec.clusterIP}')
            if [ "$cluster_ip" != "None" ] && [ -n "$cluster_ip" ]; then
                log_info "Service $service is ready with ClusterIP: $cluster_ip"
                return 0
            fi
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log_error "Service $service not ready after $((max_attempts * 2)) seconds"
    return 1
}

# Test HTTP endpoint with curl
test_http_endpoint() {
    local url=$1
    local expected_status=${2:-200}
    local description=$3
    
    log_info "Testing: $description"
    log_info "URL: $url"
    
    # Create a temporary pod for testing
    kubectl run curl-test-$$-$RANDOM \
        --image=curlimages/curl:latest \
        --restart=Never \
        --rm -i --quiet \
        --command -- curl -s -o /dev/null -w "%{http_code}" "$url" --connect-timeout 10 --max-time 30 > /tmp/http_response.txt 2>/dev/null &
    
    local curl_pid=$!
    local timeout=30
    
    # Wait for curl command with timeout
    for i in $(seq 1 $timeout); do
        if ! kill -0 $curl_pid 2>/dev/null; then
            break
        fi
        sleep 1
    done
    
    # Kill curl if still running
    kill $curl_pid 2>/dev/null || true
    wait $curl_pid 2>/dev/null || true
    
    if [ -f /tmp/http_response.txt ]; then
        local status_code=$(cat /tmp/http_response.txt)
        rm -f /tmp/http_response.txt
        
        if [ "$status_code" = "$expected_status" ]; then
            test_passed "$description - Status: $status_code"
            return 0
        else
            test_failed "$description - Expected: $expected_status, Got: $status_code"
            return 1
        fi
    else
        test_failed "$description - No response received"
        return 1
    fi
}

# Test pod readiness
test_pod_readiness() {
    local app_label=$1
    local namespace=$2
    local description=$3
    
    log_info "Testing pod readiness: $description"
    
    local ready_pods=$(kubectl get pods -n "$namespace" -l "app=$app_label" --field-selector=status.phase=Running --no-headers | wc -l)
    local total_pods=$(kubectl get pods -n "$namespace" -l "app=$app_label" --no-headers | wc -l)
    
    if [ "$ready_pods" -gt 0 ] && [ "$ready_pods" -eq "$total_pods" ]; then
        test_passed "$description - $ready_pods/$total_pods pods ready"
        return 0
    else
        test_failed "$description - Only $ready_pods/$total_pods pods ready"
        
        # Show pod details for debugging
        log_info "Pod details:"
        kubectl get pods -n "$namespace" -l "app=$app_label" || true
        
        return 1
    fi
}

# Test service endpoints
test_service_endpoints() {
    local service=$1
    local namespace=$2
    local description=$3
    
    log_info "Testing service endpoints: $description"
    
    local endpoints=$(kubectl get endpoints -n "$namespace" "$service" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
    
    if [ "$endpoints" -gt 0 ]; then
        test_passed "$description - $endpoints endpoints available"
        return 0
    else
        test_failed "$description - No endpoints available"
        
        # Show service and endpoint details
        log_info "Service details:"
        kubectl get svc -n "$namespace" "$service" || true
        kubectl get endpoints -n "$namespace" "$service" || true
        
        return 1
    fi
}

# Port-forward wrapper for testing
test_with_port_forward() {
    local service=$1
    local namespace=$2
    local local_port=$3
    local service_port=$4
    local test_path=$5
    local description=$6
    
    log_info "Testing via port-forward: $description"
    
    # Start port-forward in background
    kubectl port-forward -n "$namespace" "svc/$service" "$local_port:$service_port" >/dev/null 2>&1 &
    local pf_pid=$!
    
    # Wait a moment for port-forward to establish
    sleep 5
    
    # Test the endpoint
    local success=false
    if curl -s --connect-timeout 5 --max-time 10 "http://localhost:$local_port$test_path" >/dev/null 2>&1; then
        test_passed "$description - HTTP endpoint accessible"
        success=true
    else
        test_failed "$description - HTTP endpoint not accessible"
    fi
    
    # Clean up port-forward
    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true
    
    return $([ "$success" = true ] && echo 0 || echo 1)
}

# Main smoke tests
main() {
    echo "🌱 EcoTrack Smoke Test Suite - Environment: $ENVIRONMENT"
    echo "========================================================="
    echo "Namespace: $NAMESPACE"
    echo "Timeout: ${TIMEOUT}s"
    echo
    
    # Test 1: Demo Application
    log_info "🚀 Testing Demo Application..."
    test_pod_readiness "ecotrack-demo" "$NAMESPACE" "Demo application pods"
    test_service_endpoints "ecotrack-demo" "$NAMESPACE" "Demo application service"
    
    # Wait for service readiness
    if wait_for_service "ecotrack-demo" "80" "$NAMESPACE"; then
        test_with_port_forward "ecotrack-demo" "$NAMESPACE" "8080" "80" "/health" "Demo app health endpoint"
        test_with_port_forward "ecotrack-demo" "$NAMESPACE" "8081" "80" "/" "Demo app main page"
    fi
    
    # Test 2: Core Infrastructure Services
    log_info "🏗️ Testing Core Infrastructure..."
    
    # NGINX Ingress
    test_pod_readiness "ingress-nginx-controller" "ingress-nginx" "NGINX Ingress controller"
    test_service_endpoints "ingress-nginx-controller" "ingress-nginx" "NGINX Ingress service"
    
    # Test 3: Service Mesh
    log_info "🕸️ Testing Service Mesh..."
    test_pod_readiness "istiod" "istio-system" "Istio control plane"
    test_service_endpoints "istiod" "istio-system" "Istio service"
    
    # Test 4: Monitoring Stack
    log_info "📊 Testing Monitoring Stack..."
    
    # Prometheus
    test_pod_readiness "prometheus" "monitoring" "Prometheus"
    test_service_endpoints "monitoring-kube-prometheus-prometheus" "monitoring" "Prometheus service"
    
    if wait_for_service "monitoring-kube-prometheus-prometheus" "9090" "monitoring"; then
        test_with_port_forward "monitoring-kube-prometheus-prometheus" "monitoring" "9090" "9090" "/-/healthy" "Prometheus health"
    fi
    
    # Grafana
    test_pod_readiness "grafana" "monitoring" "Grafana"
    test_service_endpoints "monitoring-grafana" "monitoring" "Grafana service"
    
    if wait_for_service "monitoring-grafana" "80" "monitoring"; then
        test_with_port_forward "monitoring-grafana" "monitoring" "3000" "80" "/api/health" "Grafana health"
    fi
    
    # Test 5: Data Services (if deployed)
    log_info "🗄️ Testing Data Services..."
    
    # PostgreSQL
    if kubectl get statefulset -n data-services postgresql &>/dev/null; then
        test_pod_readiness "postgresql" "data-services" "PostgreSQL"
        test_service_endpoints "postgresql" "data-services" "PostgreSQL service"
    else
        log_warn "PostgreSQL not deployed, skipping test"
    fi
    
    # Redis
    if kubectl get deployment -n data-services redis-master &>/dev/null; then
        test_pod_readiness "redis" "data-services" "Redis"
        test_service_endpoints "redis-master" "data-services" "Redis service"
    else
        log_warn "Redis not deployed, skipping test"
    fi
    
    # Test 6: GitOps (ArgoCD)
    log_info "🔄 Testing GitOps..."
    
    if kubectl get deployment -n argocd argocd-server &>/dev/null; then
        test_pod_readiness "argocd-server" "argocd" "ArgoCD server"
        test_service_endpoints "argocd-server" "argocd" "ArgoCD service"
        
        if wait_for_service "argocd-server" "80" "argocd"; then
            test_with_port_forward "argocd-server" "argocd" "8080" "80" "/healthz" "ArgoCD health"
        fi
    else
        log_warn "ArgoCD not deployed, skipping test"
    fi
    
    # Test 7: Ingress and TLS
    log_info "🌐 Testing Ingress and Routing..."
    
    # Test ingress resources
    local ingresses=$(kubectl get ingress -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [ "$ingresses" -gt 0 ]; then
        test_passed "Found $ingresses ingress resources"
        
        # Show ingress details
        log_info "Ingress resources:"
        kubectl get ingress -n "$NAMESPACE" -o wide || true
    else
        test_failed "No ingress resources found"
    fi
    
    # Test 8: Security Configuration
    log_info "🔒 Testing Security Configuration..."
    
    # Test service accounts
    local service_accounts=$(kubectl get serviceaccount -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [ "$service_accounts" -gt 1 ]; then  # Always has 'default' SA
        test_passed "Found $service_accounts service accounts"
    else
        test_failed "No custom service accounts found"
    fi
    
    # Test network policies (if any)
    local network_policies=$(kubectl get networkpolicy -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [ "$network_policies" -gt 0 ]; then
        test_passed "Found $network_policies network policies"
    else
        log_warn "No network policies found (optional for dev environment)"
    fi
    
    # Summary
    echo
    echo "📊 Smoke Test Summary"
    echo "====================="
    echo "Environment: $ENVIRONMENT"
    echo "Namespace: $NAMESPACE"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo
        log_info "🎉 All smoke tests passed! Environment is ready for use."
        echo
        log_info "🔗 Access Information:"
        
        if [ "$ENVIRONMENT" = "dev" ]; then
            echo "  Demo App:    http://demo.ecotrack.local (add to /etc/hosts: 172.18.255.200)"
            echo "  Grafana:     kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80"
            echo "  Prometheus:  kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090"
            echo "  Kiali:       kubectl port-forward -n istio-system svc/kiali 20001:20001"
            echo "  Jaeger:      kubectl port-forward -n istio-system svc/jaeger 16686:16686"
        fi
        
        exit 0
    else
        echo
        log_error "⚠️  $TESTS_FAILED smoke tests failed!"
        log_error "Environment may not be fully ready for use."
        
        # Additional debugging information
        echo
        log_info "🔍 Debugging Information:"
        echo "  Check pod status: kubectl get pods -n $NAMESPACE"
        echo "  Check events:     kubectl get events -n $NAMESPACE --sort-by=.metadata.creationTimestamp"
        echo "  Check logs:       kubectl logs -n $NAMESPACE -l app=<app-name>"
        
        exit 1
    fi
}

# Cleanup function
cleanup() {
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    
    # Remove temporary files
    rm -f /tmp/http_response.txt
    
    # Clean up any test pods
    kubectl delete pod --field-selector=status.phase=Succeeded -A 2>/dev/null || true
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"