# Kyverno Default Service Account Policy

This repository contains a Kyverno policy to enforce explicit service account specification and prevent the use of default service accounts in Kubernetes/OpenShift workloads.

## Files

- **`kyverno-policy-v3-simple.yaml`** - The Kyverno ClusterPolicy that enforces explicit serviceAccountName specification
- **`kyverno-violation-report.sh`** - Bash script to generate a clean report of policy violations organized by namespace
- **`kyverno-values.yaml`** - Helm values file for installing Kyverno on OpenShift with proper security context configuration

## Policy Overview

The policy `require-explicit-service-account` prevents workloads from using the default service account by:

1. **Admission Control**: Blocks creation/update of controllers (Deployment, DaemonSet, StatefulSet, Job) that don't explicitly specify a `serviceAccountName` or set it to "default"
2. **Background Scanning**: Identifies existing pods using the default service account

### Policy Rules

- **`require-explicit-serviceaccount-controllers`**: Validates Deployment, DaemonSet, StatefulSet, and Job resources
- **`require-explicit-serviceaccount-pods`**: Validates Pod resources (for background scanning)

The policy runs in `Audit` mode by default. Change `validationFailureAction` to `Enforce` to block non-compliant resources.

## Installation

### 1. Install Kyverno using Helm

```bash
# Add Kyverno Helm repository
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

# Install Kyverno with OpenShift-compatible values
helm install kyverno kyverno/kyverno -n kyverno --create-namespace -f kyverno-values.yaml
```

### 2. Apply the Policy

```bash
# Apply the policy in Audit mode
oc apply -f kyverno-policy-v3-simple.yaml

# To enforce the policy (blocks non-compliant resources), edit the policy:
oc patch clusterpolicy require-explicit-service-account --type='merge' -p='{"spec":{"validationFailureAction":"Enforce"}}'
```

## Usage

### Generate Violation Report

```bash
# Make the script executable
chmod +x kyverno-violation-report.sh

# Run the violation report
./kyverno-violation-report.sh
```

The script will:
- Show violating workloads organized by namespace
- Trace pods back to their root controllers (Deployment, DaemonSet, etc.)
- Identify static pods separately
- Exclude specified namespaces (configurable in the script)
- Filter out automation resources

### Configure Excluded Namespaces

Edit the `EXCLUDED_NAMESPACES` variable in `kyverno-violation-report.sh`:

```bash
EXCLUDED_NAMESPACES="backend|default|frontend|kyverno|medical|operations|payments|stackrox"
```

### View Policy Status

```bash
# List all Kyverno policies
oc get cpol

# View policy details
oc describe cpol require-explicit-service-account

# View policy reports (raw)
oc get policyreports -A
```

## How to Fix Violations

### For Controllers (Deployment, DaemonSet, etc.)

Add explicit `serviceAccountName` to the pod template:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      serviceAccountName: my-custom-sa  # Add this line
      containers:
      - name: app
        image: my-app:latest
```

### For Static Pods

Edit the pod spec directly:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
spec:
  serviceAccountName: my-custom-sa  # Add this line
  containers:
  - name: app
    image: my-app:latest
```

## Policy Logic

The policy checks for two conditions that cause violations:

1. **Missing serviceAccountName**: When the field is not specified (`""`)
2. **Explicit default**: When `serviceAccountName: "default"` is explicitly set

This catches the root cause at admission time rather than after Kubernetes auto-populates the default value.

## Troubleshooting

### Policy Not Working

1. Check if Kyverno is running:
   ```bash
   oc get pods -n kyverno
   ```

2. Check policy status:
   ```bash
   oc describe cpol require-explicit-service-account
   ```

### No Policy Reports Generated

1. Check if the reports controller is running:
   ```bash
   oc get pods -n kyverno | grep reports
   ```

2. Check for events:
   ```bash
   oc get events -n kyverno
   ```

### Script Shows Empty Namespaces

This usually means resources were filtered out. Check:
- The `acs-team-temp-dev.internal` filter in the script
- Whether the violating resources are actually controllers vs individual pods

## Security Context Notes

The included `kyverno-values.yaml` is configured for OpenShift compatibility:
- Removes explicit `runAsUser` and `fsGroup` to let OpenShift assign UIDs
- Maintains security best practices (non-root, read-only filesystem, dropped capabilities)
- Uses `runAsNonRoot: true` and appropriate seccomp profiles
