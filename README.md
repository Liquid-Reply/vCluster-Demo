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
- **Allow internal DNS resolution**: vCluster runs CoreDNS on port 1053 to avoid conflicts with host cluster DNS. On EKS, DNS resolution may fail if pods are scheduled on different nodes due to restrictive security groups. Manually update the EKS node security group to allow inbound TCP and UDP traffic on port 1053 between nodes.

## Deployment

Before deploying the platform, ensure the correct host cluster kube-context is in use. The host cluster kube-context configures which Kubernetes cluster and namespace `kubectl` commands interact with. To confirm the current context, run:

### Get the current Kubernetes context

```bash
kubectl config current-context
```

Once you've confirmed the correct context, deploy the platform by running:

### Deploy the platform

```bash
vcluster platform start
```

This command deploys the platform onto the host-cluster in the `vcluster-platform` namespace. The `vcluster-platform` namespace is created automatically and serves as a dedicated space for the platform components.

The UI automatically opens in your browser and logs you in. You are asked for your user details to create the administrator user.

> **ℹ️ Info**  
> The deployment process typically takes less than 1 minute, but can take up to 2 minutes depending on your cluster's resources and network speed.

You should see output similar to the following:

### Platform installation output

```
...

##########################   LOGIN   ############################

Username: admin
Password: 27177595-21bc-4ff9-9f3a-51e0f722408b  # Change via UI or via: vcluster platform reset password

Login via UI:  https://hth45c8.loft.host
Login via CLI: vcluster platform login https://hth45c8.loft.host

#################################################################

vCluster Platform was successfully installed and can now be reached at: https://hth45c8.loft.host
Thanks for using vCluster Platform!
11:38:33 done You are successfully logged into vCluster Platform!
- Use `vcluster platform create vcluster` to create a new virtual cluster
- Use `vcluster platform add vcluster` to add an existing virtual cluster to a vCluster platform instance
```

After successful deployment, the UI automatically opens in your default web browser. You are prompted to create an administrator user.

## Configuration

The `vcluster CLI` offers various configuration options to customize the deployment process.

### Non-default Kubernetes cluster

By default, the platform is deployed to the current Kubernetes context.

#### Get the current Kubernetes context

```bash
kubectl config current-context
```

This can be overridden by specifying the `--context` flag:

#### Deploy the platform to a specific Kubernetes context

```bash
vcluster platform start --context my-cluster
```

### Custom namespace

By default, the platform is deployed to the `vcluster-platform` namespace. This can be changed by specifying the `--namespace` flag:

#### Deploy the platform to a custom namespace

```bash
vcluster platform start --namespace my-namespace
```

> **ℹ️ Info**  
> If the specified namespace does not exist, it is created automatically.