# vCluster Auto Nodes on GKE

Provision isolated, on-demand GPU nodes for multi-tenant AI training on GKE using [vCluster Auto Nodes](https://www.vcluster.com/docs/platform/auto-nodes/overview). Each tenant gets dedicated Compute Engine VMs that spin up automatically when a workload is submitted and terminate the moment it completes — no idle resources, no shared hardware, no scheduling conflicts.

All configuration files referenced in this guide are available in the [Liquid-Reply/vCluster-Demo](https://github.com/Liquid-Reply/vCluster-Demo) repository.

```bash
git clone https://github.com/Liquid-Reply/vCluster-Demo.git
cd auto-nodes
```

---

## Prerequisites

Ensure the following tools are installed and up to date:

| Tool | Minimum version |
|------|----------------|
| [gcloud CLI](https://cloud.google.com/sdk/docs/install) | v400+ |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | v1.28+ |
| [Helm](https://helm.sh/docs/intro/install/) | v3.12+ |
| [vcluster CLI](https://www.vcluster.com/docs/get-started/cli) | v0.30+ |

You also need a GCP project with GPU quota approved for your target region.

> **Note:** GPU quota requests can take 24–48 hours to process. Request quota before starting this tutorial to avoid delays when testing GPU workloads.

### Environment Variables

Define these variables once — all subsequent commands reference them:

```bash
export PROJECT_ID=your-gcp-project-id
export LOCATION=europe-west1
export CLUSTER=autonodes-demo
export PLAT_NS=vcluster-platform    # namespace where vCluster Platform runs
export KSA=loft                     # Kubernetes SA used by the Loft deployment
export GSA_NAME=vcluster            # short name of the Google SA
export GSA_EMAIL="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
```

Adjust `LOCATION` to a region with available GPU quota for your target instance types.

---

## Step 1: Enable APIs and Create the GKE Cluster

Enable the GCP APIs that power the Auto Nodes provisioning chain. `container.googleapis.com` manages GKE itself, `compute.googleapis.com` enables VM creation for private nodes, and the remaining APIs handle service account permissions and availability verification.

```bash
gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com
```

Create a GKE **Standard** cluster (not Autopilot — Autopilot's managed node lifecycle conflicts with Private Nodes, which require direct control over Compute Engine VMs). The `--workload-pool` flag enables Workload Identity so Kubernetes service accounts can authenticate to GCP APIs without static credentials.

```bash
gcloud container clusters create $CLUSTER \
  --location=$LOCATION \
  --workload-pool=$PROJECT_ID.svc.id.goog \
  --machine-type=e2-standard-4 \
  --num-nodes=3 \
  --release-channel=regular \
  --enable-ip-alias
```

Grant your user administrative permissions on the cluster:

```bash
kubectl create clusterrolebinding cluster-admin-binding \
  --clusterrole=cluster-admin \
  --user=<YOUR_EMAIL>
```

---

## Step 2: Install vCluster Platform

Deploy the vCluster Platform components into your cluster:

```bash
vcluster platform start
```

This command deploys the platform and launches the configuration UI. The platform controller orchestrates all subsequent GPU node provisioning.

**Verify:**
```bash
kubectl get pods -n $PLAT_NS
```

All pods should reach `Running` status before proceeding.

---

## Step 3: Configure IAM and Workload Identity

For vCluster Platform to provision Compute Engine VMs on your behalf, it needs authenticated access to GCP APIs. Workload Identity provides this without the security risks of static service account keys — your Kubernetes SA maps directly to a GCP SA, so Platform pods authenticate natively through GKE's identity federation.

### 3.1 Create a Custom IAM Role

Following the principle of least privilege, create a custom role with only the permissions Auto Nodes requires (Compute Engine instance management, network access, and the ability to attach service accounts to provisioned nodes):

```bash
gcloud iam roles create vClusterPlatformAutoNodes \
  --project=$PROJECT_ID \
  --file=auto-nodes-role.yaml
```

### 3.2 Create the Google Service Account

```bash
gcloud iam service-accounts create "$GSA_NAME" \
  --display-name "vCluster Platform controller"
```

### 3.3 Bind Workload Identity

This three-step process connects your Kubernetes SA (`loft` in the `vcluster-platform` namespace) to the GCP SA holding the custom Auto Nodes role:

```bash
# Allow the Kubernetes SA to impersonate the GCP SA
gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${PLAT_NS}/${KSA}]"

# Grant the GCP SA the custom Auto Nodes role
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${GSA_EMAIL}" \
  --role="projects/${PROJECT_ID}/roles/vClusterPlatformAutoNodes"

# Annotate the Kubernetes SA to complete the identity chain
kubectl -n "$PLAT_NS" annotate serviceaccount "$KSA" \
  iam.gke.io/gcp-service-account="$GSA_EMAIL" \
  --overwrite
```

**Verify** the IAM binding before proceeding:

```bash
gcloud iam service-accounts get-iam-policy $GSA_EMAIL
```

You should see the `workloadIdentityUser` role bound to your Kubernetes SA.

### 3.4 Apply the Node Provider

The node provider configuration tells vCluster Platform which Compute Engine instance types it can provision. Each entry maps a logical name to a specific GCP instance configuration, including GPU type and count:

```bash
kubectl apply -f node-provider.yaml
```

---

## Step 4: Create the vCluster

With IAM configured, create your isolated GPU environment. The `--values` flag applies the vCluster configuration that enables Private Nodes:

```bash
vcluster create auto-nodes-demo \
  --namespace auto-nodes-demo \
  --values vcluster-config.yaml \
  --driver helm
```

Connect to the vCluster — from this point, all `kubectl` commands target your isolated environment:

```bash
vcluster connect auto-nodes-demo
```

**Verify:**
```bash
vcluster list --driver helm
```

---

## Step 5: Install the NVIDIA GPU Operator

Install the GPU Operator to manage GPU resources within your vCluster. Driver installation is disabled because the node images include pre-installed NVIDIA drivers.

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update
```

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

## Step 6: Deploy a GPU Workload

Submit the test workload and watch Auto Nodes in action:

```bash
kubectl apply -f gpu-workload.yaml
```

The pod initially enters `Pending` because no GPU nodes exist yet. Karpenter detects the unschedulable pod, triggers the GCP Node Provider, and a Compute Engine VM with the configured GPU spins up automatically.

```bash
kubectl get pods -w          # watch the pod transition from Pending → Running
kubectl get nodes            # watch for the auto-provisioned GPU node to appear
```

Within 3–5 minutes a new node appears, the pod schedules onto it, runs the GPU workload, and the node terminates automatically once the job completes.

> **Note:** `gpu-workload.yaml` is a simulation — it verifies GPU access via `nvidia-smi` and uses `sleep` commands to mimic model loading and inference. For real ML workloads, replace it with PyTorch or TensorFlow jobs; the GPU resource configuration is identical.
