#!/bin/bash

set -e

echo "🔒 Starting EcoTrack Security Tests..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
SECURITY_ISSUES=0

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

security_issue() {
    SECURITY_ISSUES=$((SECURITY_ISSUES + 1))
    log_error "🔓 SECURITY ISSUE: $1"
}

# Test 1: Pod Security Context
test_pod_security_context() {
    echo "🛡️ Testing Pod Security Context..."
    
    # Get all pods and check security context
    local insecure_pods=0
    local total_pods=0
    
    while IFS= read -r pod_info; do
        if [ -n "$pod_info" ]; then
            total_pods=$((total_pods + 1))
            local namespace=$(echo "$pod_info" | awk '{print $1}')
            local pod=$(echo "$pod_info" | awk '{print $2}')
            
            # Check if pod runs as non-root
            local run_as_non_root=$(kubectl get pod -n "$namespace" "$pod" -o jsonpath='{.spec.securityContext.runAsNonRoot}' 2>/dev/null)
            local run_as_user=$(kubectl get pod -n "$namespace" "$pod" -o jsonpath='{.spec.securityContext.runAsUser}' 2>/dev/null)
            
            if [ "$run_as_non_root" != "true" ] && [ "$run_as_user" = "0" -o -z "$run_as_user" ]; then
                security_issue "Pod $namespace/$pod runs as root"
                insecure_pods=$((insecure_pods + 1))
            fi
            
            # Check read-only root filesystem
            local containers=$(kubectl get pod -n "$namespace" "$pod" -o jsonpath='{.spec.containers[*].name}')
            for container in $containers; do
                local ro_filesystem=$(kubectl get pod -n "$namespace" "$pod" -o jsonpath="{.spec.containers[?(@.name==\"$container\")].securityContext.readOnlyRootFilesystem}")
                if [ "$ro_filesystem" != "true" ]; then
                    log_warn "Container $container in pod $namespace/$pod does not have read-only root filesystem"
                fi
            done
        fi
    done < <(kubectl get pods -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name 2>/dev/null | grep -E "(ecotrack|monitoring|data-services)")
    
    local secure_pods=$((total_pods - insecure_pods))
    if [ "$insecure_pods" -eq 0 ]; then
        test_passed "All pods ($total_pods) have secure security context"
    else
        test_failed "$insecure_pods out of $total_pods pods have insecure security context"
    fi
}

# Test 2: RBAC Configuration
test_rbac() {
    echo "👤 Testing RBAC Configuration..."
    
    # Check for overly permissive service accounts
    local problematic_sa=0
    
    while IFS= read -r sa_info; do
        if [ -n "$sa_info" ]; then
            local namespace=$(echo "$sa_info" | awk '{print $1}')
            local sa=$(echo "$sa_info" | awk '{print $2}')
            
            # Skip default and system service accounts
            if [ "$sa" = "default" ] || [[ "$sa" == *"controller"* ]] || [[ "$sa" == *"operator"* ]]; then
                continue
            fi
            
            # Check cluster role bindings
            local cluster_roles=$(kubectl get clusterrolebinding -o json | jq -r --arg ns "$namespace" --arg sa "$sa" '.items[] | select(.subjects[]? | select(.kind=="ServiceAccount" and .name==$sa and .namespace==$ns)) | .roleRef.name' 2>/dev/null)
            
            for role in $cluster_roles; do
                if [[ "$role" == "cluster-admin" ]] || [[ "$role" == "admin" ]]; then
                    security_issue "Service account $namespace/$sa has overly permissive cluster role: $role"
                    problematic_sa=$((problematic_sa + 1))
                fi
            done
        fi
    done < <(kubectl get serviceaccounts -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name 2>/dev/null)
    
    if [ "$problematic_sa" -eq 0 ]; then
        test_passed "No overly permissive service accounts found"
    else
        test_failed "Found $problematic_sa service accounts with excessive permissions"
    fi
}

# Test 3: Network Policies
test_network_policies() {
    echo "🌐 Testing Network Policies..."
    
    # Check if network policies exist
    local network_policies=$(kubectl get networkpolicy -A --no-headers 2>/dev/null | wc -l)
    
    if [ "$network_policies" -gt 0 ]; then
        test_passed "Found $network_policies network policies configured"
        
        # Check for default deny policies
        local deny_policies=$(kubectl get networkpolicy -A -o json | jq -r '.items[] | select(.spec.policyTypes | contains(["Ingress"]) and (.spec.ingress | length == 0)) | .metadata.namespace + "/" + .metadata.name' 2>/dev/null | wc -l)
        
        if [ "$deny_policies" -gt 0 ]; then
            test_passed "Found $deny_policies default deny policies"
        else
            log_warn "No default deny network policies found - consider implementing them"
        fi
    else
        log_warn "No network policies found - network traffic is not restricted"
    fi
}

# Test 4: Secret Management
test_secrets() {
    echo "🗝️ Testing Secret Management..."
    
    local insecure_secrets=0
    local total_secrets=0
    
    while IFS= read -r secret_info; do
        if [ -n "$secret_info" ]; then
            total_secrets=$((total_secrets + 1))
            local namespace=$(echo "$secret_info" | awk '{print $1}')
            local secret=$(echo "$secret_info" | awk '{print $2}')
            
            # Skip system secrets
            if [[ "$secret" == *"token"* ]] || [[ "$secret" == *"ca-cert"* ]]; then
                continue
            fi
            
            # Check if secret data contains potentially sensitive information in plaintext
            local secret_data=$(kubectl get secret -n "$namespace" "$secret" -o json 2>/dev/null | jq -r '.data | to_entries[] | .key + "=" + (.value | @base64d)' 2>/dev/null | head -5)
            
            # Look for common patterns that suggest plaintext secrets
            if echo "$secret_data" | grep -iE "(password|key|token|secret)" | grep -vE "^[A-Za-z0-9+/]+=*$" >/dev/null 2>&1; then
                log_warn "Secret $namespace/$secret may contain plaintext sensitive data"
                insecure_secrets=$((insecure_secrets + 1))
            fi
        fi
    done < <(kubectl get secrets -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name 2>/dev/null | grep -v "default-token")
    
    if [ "$insecure_secrets" -eq 0 ]; then
        test_passed "All secrets appear to be properly encoded"
    else
        test_failed "$insecure_secrets out of $total_secrets secrets may have security issues"
    fi
}

# Test 5: Container Image Security
test_container_images() {
    echo "🐳 Testing Container Image Security..."
    
    local vulnerable_images=0
    local total_images=0
    local seen_images=""
    
    while IFS= read -r pod_info; do
        if [ -n "$pod_info" ]; then
            local namespace=$(echo "$pod_info" | awk '{print $1}')
            local pod=$(echo "$pod_info" | awk '{print $2}')
            
            # Get all container images in the pod
            local images=$(kubectl get pod -n "$namespace" "$pod" -o jsonpath='{.spec.containers[*].image}' 2>/dev/null)
            
            for image in $images; do
                # Skip if we've already checked this image
                if [[ "$seen_images" == *"$image"* ]]; then
                    continue
                fi
                seen_images="$seen_images $image"
                total_images=$((total_images + 1))
                
                # Check for latest tag (bad practice)
                if [[ "$image" == *":latest" ]] || [[ "$image" != *":"* ]]; then
                    security_issue "Image uses 'latest' tag or no tag: $image"
                    vulnerable_images=$((vulnerable_images + 1))
                fi
                
                # Check for known vulnerable base images (basic check)
                if [[ "$image" == *"alpine:3.1"* ]] || [[ "$image" == *"ubuntu:14"* ]] || [[ "$image" == *"centos:6"* ]]; then
                    security_issue "Image uses potentially vulnerable base image: $image"
                    vulnerable_images=$((vulnerable_images + 1))
                fi
            done
        fi
    done < <(kubectl get pods -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name 2>/dev/null | grep -E "(ecotrack|monitoring|data-services)")
    
    if [ "$vulnerable_images" -eq 0 ]; then
        test_passed "All container images ($total_images) appear secure"
    else
        test_failed "$vulnerable_images out of $total_images container images have security issues"
    fi
}

# Test 6: Resource Limits
test_resource_limits() {
    echo "⚡ Testing Resource Limits..."
    
    local pods_without_limits=0
    local total_pods=0
    
    while IFS= read -r pod_info; do
        if [ -n "$pod_info" ]; then
            total_pods=$((total_pods + 1))
            local namespace=$(echo "$pod_info" | awk '{print $1}')
            local pod=$(echo "$pod_info" | awk '{print $2}')
            
            # Check if pod has resource limits
            local has_limits=$(kubectl get pod -n "$namespace" "$pod" -o json | jq -r '.spec.containers[] | select(.resources.limits.cpu and .resources.limits.memory) | .name' 2>/dev/null | wc -l)
            local total_containers=$(kubectl get pod -n "$namespace" "$pod" -o jsonpath='{.spec.containers[*].name}' | wc -w)
            
            if [ "$has_limits" -ne "$total_containers" ]; then
                log_warn "Pod $namespace/$pod does not have resource limits on all containers"
                pods_without_limits=$((pods_without_limits + 1))
            fi
        fi
    done < <(kubectl get pods -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name 2>/dev/null | grep -E "(ecotrack|monitoring|data-services)")
    
    if [ "$pods_without_limits" -eq 0 ]; then
        test_passed "All pods have resource limits configured"
    else
        test_failed "$pods_without_limits out of $total_pods pods missing resource limits"
    fi
}

# Test 7: TLS Configuration
test_tls_configuration() {
    echo "🔐 Testing TLS Configuration..."
    
    # Check ingress TLS configuration
    local tls_ingresses=0
    local total_ingresses=0
    
    while IFS= read -r ingress_info; do
        if [ -n "$ingress_info" ]; then
            total_ingresses=$((total_ingresses + 1))
            local namespace=$(echo "$ingress_info" | awk '{print $1}')
            local ingress=$(echo "$ingress_info" | awk '{print $2}')
            
            # Check if ingress has TLS configuration
            local tls_configured=$(kubectl get ingress -n "$namespace" "$ingress" -o jsonpath='{.spec.tls}' 2>/dev/null)
            
            if [ -n "$tls_configured" ] && [ "$tls_configured" != "null" ]; then
                tls_ingresses=$((tls_ingresses + 1))
            else
                log_warn "Ingress $namespace/$ingress does not have TLS configured"
            fi
        fi
    done < <(kubectl get ingress -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name 2>/dev/null)
    
    if [ "$total_ingresses" -gt 0 ]; then
        if [ "$tls_ingresses" -eq "$total_ingresses" ]; then
            test_passed "All ingresses ($total_ingresses) have TLS configured"
        else
            test_failed "$((total_ingresses - tls_ingresses)) out of $total_ingresses ingresses missing TLS"
        fi
    else
        log_info "No ingresses found to test TLS configuration"
    fi
    
    # Check for Istio mTLS
    if kubectl get peerauthentication -A &>/dev/null; then
        local mtls_policies=$(kubectl get peerauthentication -A --no-headers | wc -l)
        if [ "$mtls_policies" -gt 0 ]; then
            test_passed "Found $mtls_policies Istio mTLS policies"
        else
            log_warn "No Istio mTLS policies found - service-to-service traffic may not be encrypted"
        fi
    fi
}

# Test 8: Admission Controllers
test_admission_controllers() {
    echo "🚪 Testing Admission Controllers..."
    
    # Check for Pod Security Standards/Pod Security Policies
    if kubectl get psp &>/dev/null; then
        local psps=$(kubectl get psp --no-headers | wc -l)
        test_passed "Found $psps Pod Security Policies"
    elif kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' | grep -E "v1\.(2[2-9]|[3-9][0-9])" >/dev/null; then
        log_info "Kubernetes version supports Pod Security Standards"
        # Check if PSS is enabled (this is a simplified check)
        if kubectl get ns kube-system -o jsonpath='{.metadata.labels}' | grep -q "pod-security"; then
            test_passed "Pod Security Standards appear to be enabled"
        else
            log_warn "Pod Security Standards may not be enabled"
        fi
    else
        log_warn "No Pod Security Policies or Standards detected"
    fi
    
    # Check for OPA Gatekeeper
    if kubectl get crd | grep gatekeeper >/dev/null 2>&1; then
        test_passed "OPA Gatekeeper is installed"
        
        local constraints=$(kubectl get constraints -A 2>/dev/null | wc -l)
        if [ "$constraints" -gt 0 ]; then
            test_passed "Found $constraints Gatekeeper constraints"
        else
            log_warn "Gatekeeper installed but no constraints found"
        fi
    else
        log_info "OPA Gatekeeper not detected (optional)"
    fi
}

# Test 9: Logging and Audit
test_logging_audit() {
    echo "📝 Testing Logging and Audit Configuration..."
    
    # Check for centralized logging
    if kubectl get pods -n kube-system | grep -E "(fluentd|fluent-bit|filebeat)" >/dev/null; then
        test_passed "Centralized logging system detected"
    else
        log_warn "No centralized logging system detected"
    fi
    
    # Check for audit logs (this is cluster-dependent)
    if kubectl get events --all-namespaces | head -1 >/dev/null 2>&1; then
        test_passed "Kubernetes events are accessible"
    else
        log_warn "Cannot access Kubernetes events"
    fi
    
    # Check for monitoring of security events
    if kubectl get servicemonitor -A 2>/dev/null | grep -q prometheus; then
        test_passed "Prometheus ServiceMonitors configured for security monitoring"
    else
        log_warn "No Prometheus ServiceMonitors found for security monitoring"
    fi
}

# Main execution
main() {
    echo "🔒 EcoTrack Platform Security Test Suite"
    echo "========================================"
    echo
    
    # Run all security tests
    test_pod_security_context
    test_rbac
    test_network_policies
    test_secrets
    test_container_images
    test_resource_limits
    test_tls_configuration
    test_admission_controllers
    test_logging_audit
    
    # Summary
    echo
    echo "📊 Security Test Summary"
    echo "========================"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo "Security Issues: $SECURITY_ISSUES"
    echo "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"
    echo
    
    if [ "$SECURITY_ISSUES" -eq 0 ] && [ "$TESTS_FAILED" -eq 0 ]; then
        log_info "🎉 All security tests passed! Platform meets security standards."
        exit 0
    elif [ "$SECURITY_ISSUES" -gt 0 ]; then
        log_error "🚨 CRITICAL: $SECURITY_ISSUES security issues found!"
        log_error "These issues should be addressed immediately."
        exit 2
    else
        log_error "⚠️  $TESTS_FAILED security tests failed."
        log_error "Review and address the security concerns above."
        exit 1
    fi
}

# Run main function
main "$@"