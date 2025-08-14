# Kyverno Default Service Account Policy

This repository helps identify OOTB OpenShift workloads which do not specify a  service account name (hence using the default SA).

## Files

- **`policy-require-explicit-service-account.yaml`** - The Kyverno ClusterPolicy that enforces explicit serviceAccountName specification
- **`kyverno-violation-report.sh`** - Bash script to generate a clean report of policy violations organized by namespace
- **`kyverno-values.yaml`** - Helm values file for installing Kyverno on OpenShift with proper security context configuration

## Policy Overview

The policy `require-explicit-service-account` catches workloads that use the default service account by:

1. **Admission Control**: Audits the creation/update of controllers (Deployment, DaemonSet, StatefulSet, Job) that don't explicitly specify a `serviceAccountName` or set it to "default"
2. **Background Scanning**: Identifies existing pods using the default service account

### Policy Rules

- **`require-explicit-serviceaccount-controllers`**: Validates Deployment, DaemonSet, StatefulSet, and Job resources
- **`require-explicit-serviceaccount-pods`**: Validates Pod resources (for background scanning)



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
oc apply -f policy-require-explicit-service-account.yaml
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
- Exclude specified demo namespaces (configurable in the script) and automation resources used by ACS "Infra" services

### Configure Excluded Namespaces

The script excludes certain namespaces from the report. Edit the `EXCLUDED_NAMESPACES` variable in `kyverno-violation-report.sh`:

```bash
EXCLUDED_NAMESPACES="backend|default|frontend|kyverno|medical|operations|payments|stackrox"
```

This is currently tuned to hide RHACS (Red Hat Advanced Cluster Security) internal demo applications .

### View Policy Status

```bash
# List all Kyverno policies
oc get cpol

# View policy details
oc describe cpol require-explicit-service-account

# View policy reports (raw)
oc get policyreports -A
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


## Security Context Notes

The included `kyverno-values.yaml` is configured for OpenShift compatibility:
- Removes explicit `runAsUser` and `fsGroup` to let OpenShift assign UIDs
- Maintains security best practices (non-root, read-only filesystem, dropped capabilities)
- Uses `runAsNonRoot: true` and appropriate seccomp profiles

---

*This project was developed with assistance from Cursor AI.*
