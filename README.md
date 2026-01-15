# vCluster-Demo

This repository showcases the power of [vCluster](https://www.vcluster.com/) - virtual Kubernetes clusters that run inside regular namespaces. vCluster provides fully functional Kubernetes clusters that are lightweight, cost-effective, and provide strong isolation while sharing the underlying host cluster resources.

## Repository Overview

This demo repository contains practical examples demonstrating key vCluster capabilities:

| Demo | Description | Key Features |
|------|-------------|--------------|
| [Resource Sharing](#resource-sharing-demo) | Share host cluster resources with vclusters | Cert Manager integration, multi-tenancy, cost optimization |
| [Auto Nodes](#auto-nodes-demo) | Automatically provision cloud compute nodes | GCP integration, GPU workloads, dynamic scaling |

---

## Resource Sharing Demo

**Location:** [`resource-sharing/`](./resource-sharing/)

This demo demonstrates vCluster's **resource sharing capabilities** by integrating Cert Manager on the host cluster with virtual clusters. It showcases how vclusters can leverage cluster-wide resources while maintaining workload isolation.

### What's Included

```
resource-sharing/
├── application-configs/          # vCluster and Cert Manager configurations
│   ├── cert-manager.yaml         # Cert Manager installation config
│   ├── vcluster.yaml             # vCluster configuration with resource sharing
│   └── configs/
│       ├── certificate.yaml      # Sample certificate resource
│       └── issuer.yaml           # ClusterIssuer configuration
├── applications/                 # Supporting applications
│   ├── external-dns.yaml         # External DNS configuration
│   ├── external-dns-policy.json  # IAM policy for External DNS
│   └── nginx-fabric.yaml         # NGINX Fabric configuration
└── host-cluster-config/          # Host cluster setup
    ├── eks-cluster.yaml          # EKS cluster configuration
    └── eks-storageclass.yaml     # Storage class for EKS
```

### Key Benefits Demonstrated

- **Single Cert Manager Installation**: One Cert Manager serves multiple vclusters
- **Resource Efficiency**: Reduced overhead by sharing infrastructure components
- **Centralized Management**: Control certificate issuers from the host cluster
- **Multi-Tenant Ready**: Teams get isolated vclusters with shared certificate infrastructure

➡️ See the full guide: [`resource-sharing/application-configs/README.md`](./resource-sharing/application-configs/README.md)

---

## Auto Nodes Demo

**Location:** [`auto-nodes/`](./auto-nodes/)

This demo showcases vCluster's **Auto Nodes** feature on Google Cloud Platform (GCP). Auto Nodes allows vclusters to automatically provision real compute nodes from cloud providers on demand, including GPU-enabled instances for AI/ML workloads.

### What's Included

```
auto-nodes/
├── README.md                 # Complete setup guide for GCP
├── auto-nodes-role.yaml      # Custom IAM role for vCluster Auto Nodes
├── node-provider.yaml        # Node provider configuration for GCP
├── vcluster-config.yaml      # vCluster configuration with Auto Nodes
├── gpu-workload.yaml         # Sample GPU workload (NVIDIA CUDA job)
└── template/                 # Terraform templates
    ├── infrastructure/       # Infrastructure provisioning (IAM, firewall, etc.)
    └── node/                 # Node template configuration
```

### Key Features Demonstrated

- **Dynamic Node Provisioning**: Automatically create compute nodes when workloads demand them
- **GPU Support**: Provision NVIDIA Tesla T4 GPU nodes for AI/ML workloads
- **GCP Integration**: Full integration with Google Cloud using Workload Identity
- **Cost Optimization**: Nodes are provisioned on-demand and can scale down when not needed
- **Customizable Node Types**: Define different node configurations (CPU, GPU, memory)

### Node Types Configured

| Node Type | Instance | Resources | Use Case |
|-----------|----------|-----------|----------|
| CPU Nodes | e2-small | 2 CPU, 2Gi RAM | General workloads |
| GPU Nodes | n1-standard-4 + T4 | 1 CPU, 3.75Gi RAM, 1 GPU | AI/ML workloads |

➡️ See the full setup guide: [`auto-nodes/README.md`](./auto-nodes/README.md)
