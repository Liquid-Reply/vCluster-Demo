1. Create Role: https://github.com/loft-sh/vcluster-auto-nodes-gcp/blob/main/docs/auto_nodes_role.yaml
2. TARGET_PROJECT="liquid-schoormann-dev-env-404"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${GSA_EMAIL}" \
  --role="projects/${PROJECT_ID}/roles/vClusterPlatformAutoNodes"

3. kubectl -n "$PLAT_NS" annotate serviceaccount "$KSA" \
  iam.gke.io/gcp-service-account="$GSA_EMAIL" \
  --overwrite

4. > kubectl create clusterrolebinding loft-admin-binding \
  --clusterrole=cluster-admin \
  --user=j.schoormann@reply.de
clusterrolebinding.rbac.authorization.k8s.io/loft-admin-binding created