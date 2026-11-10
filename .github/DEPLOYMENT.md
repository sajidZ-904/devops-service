# GitHub Actions deployment configuration

The workflows in `.github/workflows/` run validation on pull requests and build/deploy on pushes to `main`.

## GitHub configuration

In **Settings → Secrets and variables → Actions**, create:

| Name | Type | Value |
| --- | --- | --- |
| `AWS_ROLE_ARN` | Secret | ARN of the IAM role trusted for GitHub Actions OIDC from this repository's `main` branch |
| `AWS_REGION` | Variable | ECR/EC2 region, e.g. `ap-south-1` |
| `EC2_INSTANCE_ID` | Variable | Instance ID of the deployment target |

No AWS access keys are stored in GitHub. Configure the AWS IAM OIDC provider for `token.actions.githubusercontent.com` and trust only this repository and branch, with audience `sts.amazonaws.com`.

The role needs ECR authorization/token and push permissions for `devops-task-service`, plus `ssm:SendCommand`, `ssm:GetCommandInvocation`, and permission to target the selected managed instance with `AWS-RunShellScript`. Create the ECR repository once before the first run. The EC2 instance must be online and managed by Systems Manager, have Docker and `curl`, and have an instance profile permitting ECR image pulls. The security group must permit the desired inbound application traffic on port 8080.

## Image tags and releases

Each successful main-branch build publishes both the full Git commit SHA and `package.json` semantic version, for `linux/amd64` and `linux/arm64`, using GitHub Actions layer cache. Because the ECR repository may be configured with immutable tags, increment `package.json`'s version for every main-branch deployment so the version tag is unique. The SHA tag is always unique. Deployment uses the SHA tag; if `/health` does not become healthy, the remote command restores the previously running image tag and the workflow fails.

The deployment listens on port 8080 of the EC2 host and maps it to container port 3000, matching `docker-compose.yml`.
