# Setup Instructions

## Prerequisites
- AWS CLI configured with appropriate credentials (`aws sso login`)
- kubectl installed
- helm installed
- Terraform installed

## Setup

1. **Fork this repository**
   - Fork the repository on GitHub to your own account
   - Clone your fork locally:
     ```bash
     git clone git@github.com:<your-username>/support-cci-server-setup.git
     cd support-cci-server-setup
     ```

2. **Get secrets zip and unzip to root folder**
   - Download secrets from [1Password](https://start.1password.com/open/i?a=RF46QVWYHJALTBFLBRYFJHHCXU&v=wu3kikbk6yafbtv62qom3ebt5m&i=2cuzpbzqowbhhsn4j7ekp4h2wy&h=circleci.1password.com) and unzip to root folder. Should be support-cci-server-setup/secrets/

3. **Create S3 bucket for Terraform state**
   - Create an S3 bucket in your AWS account (e.g., `ka-cci-terraform-state`)
   - Update the `backend "s3"` block in `terraform/main.tf` with your bucket name

4. **Modify Terraform configuration**
   - Update `terraform/main.tf`:
     - Set `cluster_name` in locals
     - Set `region` if different
     - Update `email` with your email
     - Update `hosted_zones` with your Route53 hosted zone ARN

5. **Initialize Terraform**
   ```bash
   terraform init
   ```

6. **Deploy Infrastructure**
   ```bash
   terraform apply
   ```

7. **Connect to EKS Cluster**
   ```bash
   aws eks update-kubeconfig --name <cluster-name> --region <region>
   ```
   Replace `<cluster-name>` and `<region>` with values from your Terraform configuration.

8. **Set Environment Variables**
   ```bash
   export REPO_URL=https://github.com/<your-username>/support-cci-server-setup.git
   ```

9. **Modify Helm values.yaml file**
   - Edit `k8s/applications/values.yaml`:
     - Update `circleci-server-version` if needed
     - Update `global.domain` and `global.domainName` with your domain
     - Update `machine_provisioner.providers.ec2.subnets` with subnet IDs from Terraform output
     - Update `machine_provisioner.providers.ec2.securityGroupId` with security group ID from Terraform output
     - Update `object_storage.bucketName` to match your S3 bucket name. By default it will be `<cluster-name>-circleci-dlc`

10. **Run Bootstrap Script**
   ```bash
   cd k8s/bootstrap
   ./bootstrap.sh
   ```

11. Wait for `kubectl get pods -n circleci-server | grep kong` to be ready, then navigate to https://circleci.[yourdomain].

12. (Optional) If pods are failing you will probably need to run hacks.sh because nomad server start up sometimes due to them not all starting at the same time.

## Development

After making any changes, push to the repository. ArgoCD will automatically apply them to the cluster (refresh interval: 3 minutes).

To force an immediate refresh:
```bash
kubectl annotate app app-of-apps -n argocd argocd.argoproj.io/refresh=normal --overwrite
```

# Monitoring

Monitoring will be set up after bootstrap. Run `./portforward.sh` to port-forward these services:

You can then navigate to:

- argocd: https://localhost:8080
   - User/Pass is admin/$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
- jaeger: http://localhost:7070
- prometheus: https://localhost:9090
- nomad-server-ui: http://localhost:4646/ui/jobs


## Troubleshooting

Known issues and workarounds:

1. nomad servers need to start up together, if they don't then you need to delete all pods
   See `hacks/nomad-fix.sh`

2. policyService doesn't currently override db with new secret
   See `hacks/policy-service-fix.sh`