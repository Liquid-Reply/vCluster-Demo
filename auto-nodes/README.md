# vCluster Auto Nodes Setup Guide (GCP)

## Prerequisites

Set up your environment variables:

```bash
export PROJECT_ID=liquid-jannis-vcluster-dem-809
export LOCATION=europe-west1
export CLUSTER=autonodes-demo
export PLAT_NS=vcluster-platform    # namespace where Loft/vCluster Platform runs
export KSA=loft                     # Kubernetes SA used by the Loft deployment
export GSA_NAME=vcluster            # Short name of the Google SA
export GSA_EMAIL="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
```

---

## Step 1: Configure GCP Project & Enable APIs

```bash
gcloud config set project $PROJECT_ID
gcloud config set compute/region $LOCATION
gcloud config set compute/zone $LOCATION-b

gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com
```

**Verify:**
```bash
gcloud services list --enabled --filter="NAME:(container OR compute OR iam)"
```

---

## Step 2: Create GKE Cluster

```bash
gcloud container clusters create $CLUSTER \
  --location=$LOCATION \
  --workload-pool=$PROJECT_ID.svc.id.goog \
  --machine-type=e2-standard-4 \
  --num-nodes=3 \
  --release-channel=regular \
  --enable-ip-alias
```

**Verify:**
```bash
gcloud container clusters describe "$CLUSTER" \
  --location "$LOCATION" \
  --format="get(workloadIdentityConfig.workloadPool)"
```

---

## Step 3: Install vCluster Platform

```bash
vcluster platform start
```

**Verify:**
```bash
kubectl get pods -n $PLAT_NS
```

---

## Step 4: Create Custom IAM Role

Create the Auto Nodes IAM role using the definition from:
https://github.com/loft-sh/vcluster-auto-nodes-gcp/blob/main/docs/auto_nodes_role.yaml


```bash
gcloud iam roles create vClusterPlatformAutoNodes --project=$PROJECT_ID --file=auto_nodes_role.yaml
```

---

## Step 5: Configure Workload Identity

### 5.1 Create Kubernetes Service Account

```bash
kubectl -n "$PLAT_NS" create serviceaccount "$KSA" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 5.2 Create Google Service Account

```bash
gcloud iam service-accounts describe "$GSA_EMAIL" --format="value(email)" \
  || gcloud iam service-accounts create "$GSA_NAME" \
       --display-name "vCluster Platform controller"
```

### 5.3 Bind Workload Identity

```bash
gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${PLAT_NS}/${KSA}]"
```

### 5.4 Assign Custom Role to GSA

```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${GSA_EMAIL}" \
  --role="projects/${PROJECT_ID}/roles/vClusterPlatformAutoNodes"
```

### 5.5 Annotate Kubernetes Service Account

```bash
kubectl -n "$PLAT_NS" annotate serviceaccount "$KSA" \
  iam.gke.io/gcp-service-account="$GSA_EMAIL" \
  --overwrite
```

**Verify:**
```bash
kubectl get serviceaccount "$KSA" -n "$PLAT_NS" -o yaml | grep -A1 annotations
```

---

## Step 6: Configure RBAC & Node Provider

```bash
kubectl create clusterrolebinding loft-admin-binding \
  --clusterrole=cluster-admin \
  --user=<YOUR_EMAIL>

kubectl apply -f auto-nodes/node-provider.yaml
```

---

## Step 7: Create vCluster with Auto Nodes

```bash
vcluster create auto-nodes-demo \
  --namespace auto-nodes-demo \
  --values auto-nodes/vcluster-config.yaml \
  --driver platform
```

**Verify:**
```bash
vcluster list --driver platform
vcluster connect auto-nodes-demo
```

---

## Step 8: Install NVIDIA GPU Operator

```bash
helm install --wait gpu-operator \
  -n gpu-operator --create-namespace \
  nvidia/gpu-operator \
  --version=v25.10.1 \
  --set driver.enabled=false \
  --set toolkit.enabled=true \
  --set devicePlugin.enabled=true \
  --set dcgmExporter.enabled=true
```

**Verify:**
```bash
kubectl get pods -n gpu-operator
```

---

## Step 9: Deploy GPU Workload

```bash
kubectl apply -f auto-nodes/gpu-workload.yaml
```

**Verify:**
```bash
kubectl get pods -w
kubectl get nodes  # Watch for auto-provisioned GPU nodes
```