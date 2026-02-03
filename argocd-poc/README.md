# Argo CD POC for Langfuse Deployment

This POC demonstrates deploying Langfuse using Argo CD with GitOps principles.

## Prerequisites

- kubectl configured to access your cluster
- Helm 3.x installed
- A Kubernetes cluster (AKS/GKE/local)

## Quick Start

### 1. Install Argo CD

```bash
# Create namespace
kubectl create namespace argocd

# Install Argo CD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for Argo CD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo

# Port forward to access the UI (run in separate terminal)
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Access Argo CD UI at: https://localhost:8080
- Username: `admin`
- Password: (from command above)

### 2. Install Argo CD CLI (optional but recommended)

```bash
# macOS
brew install argocd

# Windows (with chocolatey)
choco install argocd-cli

# Linux
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/
```

Login to Argo CD CLI:
```bash
argocd login localhost:8080 --insecure --username admin --password <password>
```

### 3. Create Langfuse Secrets

Before deploying, you need to create the secrets. For POC, create them manually:

```bash
# Create langfuse namespace
kubectl create namespace langfuse

# Create secrets (replace with your actual values)
kubectl apply -f langfuse/base/secrets/secrets-example.yaml
```

For production, use:
- **Sealed Secrets** - Encrypt secrets in Git
- **External Secrets Operator** - Sync from Azure Key Vault / GCP Secret Manager
- **SOPS** - Mozilla's encrypted secrets

### 4. Deploy Langfuse with Argo CD

#### Option A: Single Environment (POC)

```bash
# Apply the Argo CD Application
kubectl apply -f langfuse/applications/langfuse-dev-dynamic.yaml

# Watch the sync status
argocd app get langfuse-dev
argocd app sync langfuse-dev

# Or via kubectl
kubectl get applications -n argocd
```

#### Option B: Multi-Environment with ApplicationSet (Recommended)

All environment configurations are defined in a single file using a list generator:

```bash
# First, update the environment values in langfuse-appset-dynamic.yaml
# Edit the generators.list.elements section with your actual values

# Apply the ApplicationSet
kubectl apply -f langfuse/applications/langfuse-appset-dynamic.yaml

# This will create one Application per environment defined in the list
kubectl get applications -n argocd
```

### 5. Verify Deployment

```bash
# Check Argo CD application status
argocd app get langfuse-dev-eu2-su1

# Check pods in langfuse namespace
kubectl get pods -n langfuse

# Check the Langfuse ingress
kubectl get ingress -n langfuse
```

## Directory Structure

```
argocd-poc/
├── README.md                              # This file
├── langfuse/
│   ├── base/                             # Base configuration (shared)
│   │   ├── secrets/                      # Secrets chart
│   │   │   ├── Chart.yaml
│   │   │   ├── templates/
│   │   │   │   └── secrets.yaml
│   │   │   └── values.yaml
│   │   └── secrets-example.yaml          # Example secrets (DO NOT commit real values)
│   │
│   ├── environments/
│   │   └── base/
│   │       └── values.yaml               # Shared Helm values (secrets refs, feature flags)
│   │
│   └── applications/
│       ├── langfuse-appset-dynamic.yaml  # ApplicationSet with all env configs in one file
│       └── langfuse-dev-dynamic.yaml     # Single app example for POC
```

## Dynamic Configuration

Environment-specific values (hostnames, database endpoints, etc.) are defined directly in the ApplicationSet generator, not in separate values.yaml files:

```yaml
# langfuse-appset-dynamic.yaml
generators:
  - list:
      elements:
        - name: dev-eu2-su1
          hostname: langfuse-dev.typeface.ai
          postgresHost: langfuse-dev-postgres.database.azure.com
          # ... all env-specific values
        - name: prod-wu2-su1
          hostname: langfuse.typeface.ai
          postgresHost: langfuse-prod-postgres.database.azure.com
          # ...
```

### Adding a New Environment

Simply add a new element to the `generators.list.elements` in `langfuse-appset-dynamic.yaml`:

```yaml
- name: prod-eu2-su1
  env: prod
  clusterUrl: https://prod-eu2-cluster.hcp.eu2.azmk8s.io:443
  chartVersion: "1.5.18"
  autoSync: "false"
  hostname: langfuse-eu.typeface.ai
  postgresHost: langfuse-prod-eu-postgres.database.azure.com
  clickhouseHost: langfuse-prod-eu-clickhouse.typeface.ai
  clickhouseMigrationUrl: https://langfuse-prod-eu-clickhouse.typeface.ai:8443
  redisHost: langfuse-prod-eu.redis.cache.windows.net
  storageBucket: langfuse-prod-eu-data
  storageEndpoint: https://langfuseprodeusa.blob.core.windows.net
```

Then commit and push - Argo CD will automatically create the new Application.

## How It Works

### Current Flow (Azure DevOps)
```
ADO Pipeline → envsubst values → helm upgrade → cluster
```

### New Flow (GitOps with Argo CD)
```
Git commit (config change) → Argo CD detects → helm upgrade → cluster(s)
```

### Key Differences

| Aspect | Current (ADO) | GitOps (Argo CD) |
|--------|---------------|------------------|
| Trigger | Manual pipeline run | Git commit (auto-sync) |
| State | Transient (in pipeline) | Persistent (in Git) |
| Rollback | Re-run old pipeline | Git revert |
| Multi-cluster | Separate stages | Single ApplicationSet |
| Audit | ADO logs | Git history |
| Config | Separate values.yaml per env | All envs in one file |

## Simulating a Release

### Upgrade Chart Version

Edit `langfuse-appset-dynamic.yaml` and update the `chartVersion` for the target environment:

```bash
# Edit the ApplicationSet
# Change chartVersion from "1.5.18" to "1.5.19" for dev-eu2-su1

# Commit and push
git add langfuse/applications/langfuse-appset-dynamic.yaml
git commit -m "Upgrade langfuse to v1.5.19 in dev"
git push

# Argo CD will auto-sync, or manually sync
argocd app sync langfuse-dev-eu2-su1
```

### Update Configuration

Edit the environment's values in the list generator:

```bash
# Change hostname, database endpoint, etc. in langfuse-appset-dynamic.yaml

git add langfuse/applications/langfuse-appset-dynamic.yaml
git commit -m "Update dev postgres endpoint"
git push
```

## Troubleshooting

```bash
# Check application status
argocd app get langfuse-dev-eu2-su1

# View sync details
argocd app diff langfuse-dev-eu2-su1

# Force sync
argocd app sync langfuse-dev-eu2-su1 --force

# Check Argo CD logs
kubectl logs -n argocd deployment/argocd-repo-server
kubectl logs -n argocd deployment/argocd-application-controller

# View rendered Helm values
argocd app manifests langfuse-dev-eu2-su1
```

## Next Steps for Production

1. **Secrets Management**: Integrate External Secrets Operator with Azure Key Vault
2. **RBAC**: Set up Argo CD projects and RBAC for team access
3. **Notifications**: Configure Argo CD notifications to Slack/Teams
4. **Image Updater**: Set up Argo CD Image Updater for automatic updates
5. **HA Setup**: Deploy Argo CD in HA mode for production
