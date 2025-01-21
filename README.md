# vCluster-Demo
## Prerequisites
### Tools
- **kubectl**: Install the Kubernetes command-line tool to interact with your cluster.
- **vCluster CLI**: Install the vCluster command-line interface.
- **AWS CLI**: Install and configure the AWS Command Line Interface.
- **eksctl**: Install eksctl for EKS cluster management.

### EKS Cluster
- **EBS-CSI Driver**: The driver add-on is needed to ensure proper EBS storage provisioning, which is required by vCluster to store data for virtual clusters.
- **Storage Class**: vCluster requires a default StorageClass for its persistent volumes. EKS provides the gp2 StorageClass by default, but gp3 is required. Create a new StorageClass and remove the default status from the gp2 StorageClass:
```
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```