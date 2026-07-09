# vCluster DRA Whole GPU and GPU Slice Sync

This demo shows Kubernetes Dynamic Resource Allocation, DRA, with vCluster Platform selector-based sync for tenant GPU isolation.

The point of the demo is:

- `legal-ai` gets access to a whole GPU class.
- `research-ai` gets access only to a GPU slice class.
- `DeviceClass` objects are created only on the host Kubernetes cluster.
- vCluster syncs only the allowed `DeviceClass` into each tenant vCluster by label selector.
- Teams create `ResourceClaim` objects inside their vCluster.
- vCluster syncs those `ResourceClaim` objects back to the host cluster.
- No admission policy is used in this version of the demo.

The GPU slice path uses NVIDIA MIG. T4 GPUs cannot demonstrate this because T4 does not support MIG. This guide uses A100 40GB Spot nodes because A100 is the lowest-cost commonly available NVIDIA GPU class on GKE that supports the `1g.5gb` MIG profile.

```text
Host cluster
|-- DeviceClass/gpu-whole
|   labels:
|     gpu.platform/tenant: legal-ai
|     gpu.platform/allocation: whole
|   selects:
|     driver: gpu.nvidia.com
|
|-- DeviceClass/gpu-slice
|   labels:
|     gpu.platform/tenant: research-ai
|     gpu.platform/allocation: slice
|   selects:
|     driver: mig.nvidia.com
|     profile: 1g.5gb
|
|-- vCluster: legal-ai
|   |-- sees only DeviceClass/gpu-whole
|   `-- syncs legal whole-GPU ResourceClaims to host
|
`-- vCluster: research-ai
    |-- sees only DeviceClass/gpu-slice
    `-- syncs research GPU-slice ResourceClaims to host
```

The key vCluster sync behavior is:

```yaml
sync:
  toHost:
    resourceClaims:
      enabled: true

  fromHost:
    deviceClasses:
      enabled: true
      selector:
        matchLabels:
          gpu.platform/tenant: legal-ai
```

That means:

- `DeviceClasses` are owned by the host platform team.
- Each vCluster receives only `DeviceClasses` matching its tenant label.
- `ResourceClaims` are created by teams inside their vCluster and synced back to the host.
- Tenant labels on `ResourceClaims` remain useful for auditing and host-side visibility. In this tested vCluster version, the label selector belongs on `fromHost.deviceClasses`; `toHost.resourceClaims` is enabled but not label-filtered in the vCluster config.

## Files

```text
dra-gpu-sync/
|-- README.md
|-- gpu-deviceclasses.yaml
|-- research-ai-vcluster-config.yaml
|-- legal-ai-vcluster-config.yaml
|-- legal-whole-gpu-resourceclaim.yaml
|-- contract-summarizer-dra.yaml
|-- research-gpu-slice-resourceclaim.yaml
`-- research-training-dra.yaml
```

## Prerequisites

| Tool | Minimum version |
|---|---|
| `gcloud` CLI | v400+ |
| `kubectl` | v1.28+ |
| Helm | v3.12+ |
| vCluster CLI | v0.30+ |

You also need:

- Quota for A100 GPUs in your target GCP region and zone.
- vCluster Platform installed and licensed for DRA Sync.

> Important: DRA sync is a vCluster Platform feature. If Platform is not installed or your license does not include DRA Sync, the vCluster syncer exits with an error like `you are trying to use a vCluster pro feature 'DRA Sync'`.

Clone the repository:

```bash
git clone https://github.com/Liquid-Reply/vCluster-Demo.git
cd vCluster-Demo
```

Set environment variables:

```bash
export PROJECT_ID=your-gcp-project-id
export CLUSTER=dra-gpu-sync-demo
export PLAT_NS=vcluster-platform
export GPU_TYPE=nvidia-tesla-a100
export GPU_MACHINE_TYPE=a2-highgpu-1g
export MIG_PROFILE=1g.5gb
export WHOLE_GPU_NODEPOOL=a100-whole-pool
export SLICE_GPU_NODEPOOL=a100-mig-1g5gb-pool

gcloud config set project $PROJECT_ID
```

Before creating the cluster, choose a zone that offers the MIG-capable GPU type. The cluster region must match the selected GPU zone's region.

Find zones that offer A100:

```bash
gcloud compute accelerator-types list \
  --filter="name=($GPU_TYPE)" \
  --format="table(name,zone)"
```

Pick a zone from the output and set `GPU_ZONE` and `LOCATION`. For example, if the output includes `europe-west4-a`, set:

```bash
export GPU_ZONE=europe-west4-a
export LOCATION=europe-west4
```

Check that A100 is available in the selected zone:

```bash
gcloud compute accelerator-types describe $GPU_TYPE \
  --zone=$GPU_ZONE
```

Do not create the cluster until `LOCATION` and `GPU_ZONE` are set correctly. A GKE regional cluster in `europe-west1` cannot use GPU node pools from `europe-west4-a`.

## Step 1: Enable APIs and Create the GKE Cluster

Enable the required APIs:

```bash
gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com
```

Create the GKE Standard cluster:

```bash
gcloud container clusters create $CLUSTER \
  --location=$LOCATION \
  --machine-type=e2-standard-4 \
  --num-nodes=1 \
  --release-channel=regular \
  --enable-ip-alias
```

Get credentials:

```bash
gcloud container clusters get-credentials $CLUSTER \
  --location=$LOCATION
```

Grant your user admin permissions:

```bash
kubectl create clusterrolebinding cluster-admin-binding \
  --clusterrole=cluster-admin \
  --user=<YOUR_EMAIL>
```

Verify:

```bash
kubectl get nodes
```

## Step 2: Install vCluster Platform

Install vCluster Platform before creating the tenant vClusters. This is the same Platform setup pattern used by the Auto Nodes guide in `auto-nodes/README.md`.

Start Platform:

```bash
vcluster platform start
```

The command deploys Platform into the cluster and opens the configuration UI.

Verify the Platform pods:

```bash
kubectl get pods -n $PLAT_NS
```

All pods should reach `Running` status before continuing.

Make sure your Platform installation is licensed for DRA Sync. Without that license, the tenant vClusters can be created, but the syncer will crash when `resourceClaims` or `deviceClasses` sync is enabled.

Verify that the CLI is logged into Platform and can see the default project:

```bash
vcluster platform list projects
```

You should see at least:

```text
default
```

Also verify your local tools:

```bash
helm version
vcluster version
```

## Step 3: Configure Host GPU and DRA Support

Create two small Spot GPU node pools on the host cluster:

- `a100-whole-pool`: exposes one whole A100 GPU for the legal tenant.
- `a100-mig-1g5gb-pool`: exposes A100 MIG `1g.5gb` slices for the research tenant.

These are not cheap like T4, but this is the lowest-cost realistic path for a true whole-GPU versus hardware-sliced-GPU demo on GKE. Use Spot VMs and delete the pools after the demo.

Create the whole-GPU node pool with GKE-managed NVIDIA driver installation:

```bash
gcloud container node-pools create $WHOLE_GPU_NODEPOOL \
  --cluster=$CLUSTER \
  --location=$LOCATION \
  --node-locations=$GPU_ZONE \
  --machine-type=$GPU_MACHINE_TYPE \
  --accelerator=type=$GPU_TYPE,count=1,gpu-driver-version=latest \
  --num-nodes=1 \
  --image-type=COS_CONTAINERD \
  --enable-autoscaling \
  --min-nodes=0 \
  --max-nodes=1 \
  --node-taints=nvidia.com/gpu=present:NoSchedule
```

Create the MIG-sliced GPU node pool with one A100 split into seven `1g.5gb` slices:

```bash
gcloud container node-pools create $SLICE_GPU_NODEPOOL \
  --cluster=$CLUSTER \
  --location=$LOCATION \
  --node-locations=$GPU_ZONE \
  --machine-type=$GPU_MACHINE_TYPE \
  --accelerator=type=$GPU_TYPE,count=1,gpu-partition-size=$MIG_PROFILE,gpu-driver-version=latest \
  --num-nodes=1 \
  --image-type=COS_CONTAINERD \
  --enable-autoscaling \
  --min-nodes=0 \
  --max-nodes=1 \
  --node-taints=nvidia.com/gpu=present:NoSchedule
```

Verify the node pools:

```bash
gcloud container node-pools list \
  --cluster=$CLUSTER \
  --location=$LOCATION
```

Wait for the GPU nodes to join the cluster:

```bash
kubectl get nodes -w
```

Verify the MIG node label:

```bash
kubectl get nodes \
  -l cloud.google.com/gke-gpu-partition-size=$MIG_PROFILE \
  --show-labels
```

Install the NVIDIA DRA driver on the host cluster. On GKE, set `nvidiaDriverRoot=/home/kubernetes/bin/nvidia` so the DRA driver uses the GKE-managed NVIDIA driver path.

```bash
helm install dra-driver-nvidia-gpu \
  oci://registry.k8s.io/dra-driver-nvidia/charts/dra-driver-nvidia-gpu \
  --version 0.4.0 \
  --namespace dra-driver-nvidia-gpu \
  --create-namespace \
  --set gpuResourcesEnabledOverride=true \
  --set resources.computeDomains.enabled=false \
  --set nvidiaDriverRoot=/home/kubernetes/bin/nvidia
```

Verify that the DRA driver pods are running:

```bash
kubectl get pods -n dra-driver-nvidia-gpu
```

Verify that the NVIDIA DRA driver registered its default GPU classes:

```bash
kubectl get deviceclasses
```

You should see classes such as:

```text
gpu.nvidia.com
mig.nvidia.com
vfio.gpu.nvidia.com
```

Verify that the GPU nodes publish `ResourceSlice` objects for whole GPU and MIG devices:

```bash
kubectl get resourceslices -o wide
```

You should see slices with drivers like:

```text
gpu.nvidia.com
mig.nvidia.com
```

After the demo, scale the GPU node pools back to zero or delete them to avoid idle GPU cost:

```bash
gcloud container clusters resize $CLUSTER \
  --location=$LOCATION \
  --node-pool=$WHOLE_GPU_NODEPOOL \
  --num-nodes=0

gcloud container clusters resize $CLUSTER \
  --location=$LOCATION \
  --node-pool=$SLICE_GPU_NODEPOOL \
  --num-nodes=0
```

Or delete the node pools completely:

```bash
gcloud container node-pools delete $WHOLE_GPU_NODEPOOL \
  --cluster=$CLUSTER \
  --location=$LOCATION

gcloud container node-pools delete $SLICE_GPU_NODEPOOL \
  --cluster=$CLUSTER \
  --location=$LOCATION
```

> Important: the NVIDIA device plugin exposes classic `nvidia.com/gpu` resources. DRA requires the NVIDIA DRA driver installed above. The regular device plugin alone is not the same as DRA.

## Step 4: Check DRA API Availability on the Host Cluster

Make sure your current `kubectl` context points to the host cluster:

```bash
kubectl config current-context
```

Check that the DRA resources exist:

```bash
kubectl api-resources | grep resource.k8s.io
```

You should see resources such as:

```text
deviceclasses
resourceclaims
resourceslices
```

Check whether `DeviceClass` is available:

```bash
kubectl get deviceclasses
```

## Step 5: Create Platform-Owned DeviceClasses on the Host Cluster

Apply the host-owned `DeviceClass` objects:

```bash
kubectl apply -f dra-gpu-sync/gpu-deviceclasses.yaml
```

Verify:

```bash
kubectl get deviceclasses --show-labels
```

Expected:

```text
NAME         LABELS
gpu-slice    gpu.platform/tenant=research-ai,gpu.platform/allocation=slice,...
gpu-whole    gpu.platform/tenant=legal-ai,gpu.platform/allocation=whole,...
```

The important selectors are:

```yaml
gpu-whole: device.driver == 'gpu.nvidia.com'
gpu-slice: device.driver == 'mig.nvidia.com' && device.attributes['gpu.nvidia.com'].profile == '1g.5gb'
```

That is what makes the demo real: `gpu-whole` selects a full GPU device, while `gpu-slice` selects only a MIG slice.

## Step 6: Create the Research vCluster with GPU Slice Sync

Create the vCluster through vCluster Platform. This must be created while logged into vCluster Platform. Do not pass `--add=false` for this demo.

```bash
vcluster create research-ai \
  --driver platform \
  --project default \
  --cluster loft-cluster \
  --values dra-gpu-sync/research-ai-vcluster-config.yaml \
  --connect=false
```

Wait until Platform reports the vCluster as ready:

```bash
vcluster list --driver platform
```

Connect to the research vCluster:

```bash
vcluster connect research-ai --namespace research-ai
```

Verify that only the research GPU slice class is visible:

```bash
kubectl get deviceclasses --show-labels
```

Expected:

```text
NAME        LABELS
gpu-slice   gpu.platform/tenant=research-ai,gpu.platform/allocation=slice,...
```

The research vCluster should not see `gpu-whole`.

## Step 7: Create the Legal vCluster with Whole GPU Sync

Switch back to the host cluster context.

Create the vCluster through vCluster Platform. This must be created while logged into vCluster Platform. Do not pass `--add=false` for this demo.

```bash
vcluster create legal-ai \
  --driver platform \
  --project default \
  --cluster loft-cluster \
  --values dra-gpu-sync/legal-ai-vcluster-config.yaml \
  --connect=false
```

Wait until Platform reports the vCluster as ready:

```bash
vcluster list --driver platform
```

Connect to the legal vCluster:

```bash
vcluster connect legal-ai --namespace legal-ai
```

Verify that only the legal whole GPU class is visible:

```bash
kubectl get deviceclasses --show-labels
```

Expected:

```text
NAME        LABELS
gpu-whole   gpu.platform/tenant=legal-ai,gpu.platform/allocation=whole,...
```

The legal vCluster should not see `gpu-slice`.

## Step 8: Legal Team Creates a Whole GPU ResourceClaim

Connect to the legal vCluster:

```bash
vcluster connect legal-ai --namespace loft-default-v-legal-ai
```

Apply the legal claim:

```bash
kubectl apply -f dra-gpu-sync/legal-whole-gpu-resourceclaim.yaml
```

Verify inside the vCluster:

```bash
kubectl get resourceclaims
```

The legal vCluster syncs `ResourceClaim` objects to the host. The `gpu.platform/tenant: legal-ai` label is preserved on the host-side synced claim for auditing and visibility.

## Step 9: Deploy the Legal Whole GPU Workload

Apply the workload:

```bash
kubectl apply -f dra-gpu-sync/contract-summarizer-dra.yaml
```

Watch the workload:

```bash
kubectl get pods -w
```

Expected behavior:

1. The Pod references `legal-whole-gpu`.
2. The `ResourceClaim` references `DeviceClass/gpu-whole`.
3. `DeviceClass/gpu-whole` selects `device.driver == 'gpu.nvidia.com'`.
4. vCluster syncs the `ResourceClaim` to the host cluster.
5. The host cluster DRA driver allocates a whole GPU device.

Check what the legal workload sees:

```bash
kubectl logs contract-summarizer
```

The output should show a whole A100 GPU, not a MIG device.

## Step 10: Verify Legal Claim from the Host Cluster

Switch back to the host cluster context.

Check synced `ResourceClaims`:

```bash
kubectl get resourceclaims -A
```

Inspect the legal claim allocation:

```bash
kubectl get resourceclaims -A -o yaml | grep -A20 legal-whole-gpu
```

The allocation should refer to a device from the `gpu.nvidia.com` driver.

## Step 11: Research Team Creates a GPU Slice ResourceClaim

Connect to the research vCluster:

```bash
vcluster connect research-ai --namespace research-ai
```

Verify that research only sees `gpu-slice`:

```bash
kubectl get deviceclasses
```

Expected:

```text
NAME
gpu-slice
```

Apply the research claim:

```bash
kubectl apply -f dra-gpu-sync/research-gpu-slice-resourceclaim.yaml
```

Apply the research workload:

```bash
kubectl apply -f dra-gpu-sync/research-training-dra.yaml
```

Watch the Pod:

```bash
kubectl get pods -w
```

Expected behavior:

1. The research Pod uses `research-gpu-slice`.
2. The claim references `DeviceClass/gpu-slice`.
3. `DeviceClass/gpu-slice` selects `device.driver == 'mig.nvidia.com'` and profile `1g.5gb`.
4. vCluster syncs the matching claim to the host.
5. The host cluster DRA driver allocates a MIG GPU slice.

Check what the research workload sees:

```bash
kubectl logs research-training-job
```

The output should show a MIG device similar to:

```text
MIG 1g.5gb Device 0
```

## Step 12: Verify Research Claim from the Host Cluster

Switch back to the host cluster context.

Check synced `ResourceClaims`:

```bash
kubectl get resourceclaims -A
```

Inspect the research claim allocation:

```bash
kubectl get resourceclaims -A -o yaml | grep -A20 research-gpu-slice
```

The allocation should refer to a device from the `mig.nvidia.com` driver.

## Step 13: Verify Tenant GPU Class Isolation

Connect to legal:

```bash
vcluster connect legal-ai --namespace legal-ai
kubectl get deviceclasses --show-labels
```

Expected:

```text
NAME        LABELS
gpu-whole   gpu.platform/tenant=legal-ai,gpu.platform/allocation=whole,...
```

Connect to research:

```bash
vcluster connect research-ai --namespace research-ai
kubectl get deviceclasses --show-labels
```

Expected:

```text
NAME        LABELS
gpu-slice   gpu.platform/tenant=research-ai,gpu.platform/allocation=slice,...
```

This is the core selector-based demo:

```text
Host cluster owns tenant DeviceClasses.
Legal vCluster receives only the whole-GPU DeviceClass.
Research vCluster receives only the MIG-slice DeviceClass.
Teams create ResourceClaims in their vCluster.
ResourceClaims sync back to the host.
The host NVIDIA DRA driver allocates either a whole GPU or a MIG slice.
```
