# vcluster Resource Sharing with Cert Manager

This guide demonstrates how to use vcluster's resource sharing capabilities by installing Cert Manager on the host cluster and using it to generate certificates within a vcluster. This showcases one of vcluster's key advantages: sharing cluster-wide resources while maintaining workload isolation.

## Architecture Overview

```
Host Cluster
├── Cert Manager (installed)
├── ClusterIssuer (selfsigned-issuer)
└── vcluster
    ├── Certificate resource (synced to host)
    └── Generated TLS Secret (synced back)
```

## Prerequisites

- Kubernetes cluster (host cluster)
- kubectl configured
- vcluster CLI installed
- Helm (optional, for easier Cert Manager installation)

## Step-by-Step Implementation

### Step 1: Install Cert Manager on Host Cluster

Install Cert Manager using the official manifests:

```bash
# Install Cert Manager CRDs and components
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml

```

### Step 2: Create ClusterIssuer on Host Cluster

Create the ClusterIssuer resource:

```bash
# Save as clusterissuer.yaml
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF
```

Verify the ClusterIssuer is ready:

```bash
kubectl get clusterissuer selfsigned-issuer -o wide
```

### Step 3: Configure vcluster with Resource Sharing

Create your vcluster configuration file:

```bash
# Save as vcluster-values.yaml
cat <<EOF > vcluster-values.yaml
sync:
  toHost:
    ingresses:
      enabled: true
integrations:
  certManager:
    enabled: true
controlPlane:
  coredns:
    enabled: true
    embedded: true
EOF
```

### Step 4: Create and Connect to vcluster

```bash
# Create the vcluster
vcluster create demo-cluster -f vcluster-values.yaml

# Connect to the vcluster (this switches your kubectl context)
vcluster connect demo-cluster
```

### Step 5: Create Certificate in vcluster

Now, working within the vcluster context, create the Certificate resource:

```bash
# Save as certificate.yaml
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-com
  namespace: default
spec:
  secretName: example-com-tls
  dnsNames:
  - example.com
  - www.example.com
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
EOF
```

### Step 6: Verify Certificate Generation

Check the certificate status within the vcluster:

```bash
# Check certificate status
kubectl get certificate example-com -o wide

# Check if the secret was created
kubectl get secret example-com-tls

# View certificate details
kubectl describe certificate example-com
```

### Step 7: Verify Resource Sharing on Host Cluster

Switch back to the host cluster context to see the synced resources:

```bash
# Disconnect from vcluster (returns to host context)
vcluster disconnect

# Check synced certificate on host cluster
kubectl get certificate -A | grep example-com

# Check synced secret on host cluster
kubectl get secret -A | grep example-com-tls
```

## Key Benefits of This Approach

### 1. **Resource Efficiency**
- **Single Cert Manager Installation**: One Cert Manager installation serves multiple vclusters
- **Reduced Resource Overhead**: No need to install Cert Manager in each vcluster
- **Centralized Management**: Manage all certificate issuers from the host cluster

### 2. **Cost Optimization**
- **Shared Infrastructure**: Multiple teams can share the same Cert Manager setup
- **Reduced Compute Requirements**: Lower overall resource consumption
- **Simplified Operations**: Fewer components to maintain and update

### 3. **Security and Compliance**
- **Centralized Certificate Management**: Consistent certificate policies across all vclusters
- **Controlled Access**: Host cluster admins control certificate issuers
- **Audit Trail**: Centralized logging and monitoring of certificate operations

### 4. **Operational Benefits**
- **Simplified Upgrades**: Update Cert Manager once for all vclusters
- **Consistent Configuration**: Same certificate issuers available everywhere
- **Reduced Complexity**: Teams don't need to manage Cert Manager individually

## Use Cases and Extensions

### Multi-Tenant Scenarios
- **Development Teams**: Each team gets their own vcluster but shares certificate infrastructure
- **Environment Separation**: Different vclusters for dev/staging/prod with shared certificate management
- **Customer Isolation**: SaaS providers can offer isolated environments while managing certificates centrally

### Integration Patterns
- **GitOps Workflows**: Certificate resources can be managed through Git repositories
- **Automated Renewals**: Cert Manager handles renewals automatically across all vclusters
- **Monitoring Integration**: Centralized monitoring of certificate expiration and health

This example demonstrates vcluster's power in creating efficient, shared infrastructure while maintaining the isolation benefits of separate Kubernetes clusters.