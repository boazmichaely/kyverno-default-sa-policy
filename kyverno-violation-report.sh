#!/bin/bash

# Kyverno Policy Violation Report - Default Service Account Check
# Excludes specified namespaces and shows workloads using default service account

# Configuration - Add/remove namespaces to exclude
EXCLUDED_NAMESPACES="backend|default|frontend|kyverno|medical|operations|payments|stackrox"

# Function to find the root owner of a resource
find_root_owner() {
    local namespace=$1
    local kind=$2
    local name=$3
    
    # Define root controller types (these don't typically have owners)
    local root_types="Deployment|StatefulSet|DaemonSet|Job|CronJob"
    
    # If this is already a root type, return it
    if [[ $kind =~ ^($root_types)$ ]]; then
        echo "$kind: $name"
        return
    fi
    
    # Get owner reference
    local owner_info=$(oc get "$kind" "$name" -n "$namespace" -o json 2>/dev/null | \
        jq -r '.metadata.ownerReferences[]? | select(.controller == true) | "\(.kind):\(.name)"')
    
    if [ -n "$owner_info" ]; then
        local owner_kind=$(echo "$owner_info" | cut -d: -f1)
        local owner_name=$(echo "$owner_info" | cut -d: -f2)
        
        # If owner is a Node, treat the pod as a static pod (root resource)
        if [ "$owner_kind" = "Node" ]; then
            echo "Pod: $name (static)"
        else
            # Recursively find the root owner
            find_root_owner "$namespace" "$owner_kind" "$owner_name"
        fi
    else
        # No owner found, this is the root
        echo "$kind: $name"
    fi
}

echo "OpenShift Resources using default service account"
echo "================================"

# Get all namespaces with violations, excluding specified ones
violating_namespaces=$(oc get policyreports -A -o json | \
    jq -r ".items[] | select(.metadata.namespace | test(\"^($EXCLUDED_NAMESPACES)\$\") | not) | select(.summary.fail > 0) | .metadata.namespace" | \
    sort | uniq)

if [ -z "$violating_namespaces" ]; then
    echo "No policy violations found in non-excluded namespaces!"
    exit 0
fi

for namespace in $violating_namespaces; do
    # Get violation details and find root owners, excluding automation resources
    violations=$(oc get policyreports -n "$namespace" -o json | \
        jq -r '.items[] | select(.summary.fail > 0) | 
        "\(.scope.kind) \(.scope.name)"' | \
    while read kind name; do
        # Skip resources ending with 'acs-team-temp-dev.internal'
        if [[ "$name" == *"acs-team-temp-dev.internal" ]]; then
            continue
        fi
        root_owner=$(find_root_owner "$namespace" "$kind" "$name")
        echo "$root_owner"
    done | sort | uniq)
    
    # Only print namespace header if there are actual violations to show
    if [ -n "$violations" ]; then
        echo ""
        echo "NAMESPACE: ${namespace}"
        echo "$(printf '%.s-' {1..50})"
        echo "$violations"
    fi
done


