# DevOps Task Service

Production-oriented Node.js service with containerization, CI/CD, AWS Terraform, Kubernetes, observability, and Linux automation.

## Quick start

Prerequisites: Node.js 22+, npm, Docker Compose v2, and (for optional sections) Terraform 1.6+, kubectl, and a local Kubernetes cluster with metrics-server.

```bash
npm ci
cp .env.example .env
npm test
npm run lint
docker compose up --build
curl http://localhost:8080/health
```

The service exposes `/`, `/health`, and Prometheus metrics at `/metrics`. Configuration comes from `PORT`, `LOG_LEVEL`, `ENVIRONMENT`, and `APP_VERSION`; supported environments are `local`, `test`, `development`, `staging`, and `production`. Logs are JSON on stdout. The Alpine runtime image is approximately 150 MB compressed; verify the exact platform result with `docker image ls`.

### WSL 2

Run commands from the WSL filesystem (`/mnt/c/devops-service-task` or a Linux home directory). Docker Desktop must have WSL integration enabled for the distribution, or a Docker Engine must be running inside WSL. Before running the health script, use `chmod +x scripts/*.sh`; Docker host mounts in the monitoring Compose file require Docker Desktop/Engine access to `/var/run/docker.sock` and `/var/lib/docker`.

Keep the GitHub runner outside the repository, for example at `~/actions-runner`; the runner contains registration credentials and must never be committed.

If GitHub Actions is unavailable because of an account billing lock, run the complete local validation pipeline from WSL 2:

```bash
chmod +x scripts/*.sh
bash scripts/local_pipeline.sh
```

To publish the tested image manually, authenticate to a registry and set its image name:

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USER --password-stdin
IMAGE_URI=ghcr.io/OWNER/REPOSITORY:$(git rev-parse --short HEAD) bash scripts/local_pipeline.sh
docker push ghcr.io/OWNER/REPOSITORY:$(git rev-parse --short HEAD)
```

This avoids GitHub-hosted runner minutes. AWS deployment still requires an AWS account, an EC2/SSM target, and permissions; without those, the local smoke test is the safe deployment substitute.

## CI/CD

`.github/workflows/ci.yml` runs lint, tests/coverage, Hadolint, ShellCheck, an image build, and a Trivy CRITICAL vulnerability gate on pull requests. [deploy.yml](./.github/workflows/deploy.yml) handles pushes to `main`: it builds and pushes `linux/amd64` and `linux/arm64` images to ECR with the commit SHA and `package.json` semantic version, uses Actions layer caching, deploys through SSM, publishes the container on host port 80 to match the security group, waits for `/health`, and restores the previous image if the smoke test fails.

Configure the repository secret `AWS_ROLE_ARN` and the repository variable `EC2_INSTANCE_ID`; the optional `AWS_REGION` variable overrides the workflow's `ap-south-1` default. The assumed IAM role needs ECR push permissions plus `ssm:SendCommand` and `ssm:GetCommandInvocation`, and it is trusted through GitHub OIDC, never static keys. Create the ECR repository `devops-task-service` in the target region before the first run: the build job verifies it exists and, when it is absent, prints the `aws ecr create-repository` command instead of failing later inside Docker. Both jobs validate their configuration before calling AWS and name the specific missing secret or variable.

## AWS Terraform

The code provisions an EC2 target in the default VPC, HTTP security group, least-privilege instance role, SSM access, CloudWatch Logs with 30-day retention, and Docker bootstrap. `environment` supports `staging` and `production`. The region defaults to `ap-south-1`; pass `-var='aws_region=...'` to target another one, including when destroying resources created there.

```bash
cd terraform
cp backend.tf.example backend.tf
terraform init
terraform plan -var='state_bucket=my-state-bucket' -var='app_image=<account-id>.dkr.ecr.ap-south-1.amazonaws.com/devops-task-service:1.0.0'
terraform apply -var='state_bucket=my-state-bucket' -var='app_image=...'
terraform destroy -var='state_bucket=my-state-bucket' -var='app_image=...'
```

Use an existing versioned/encrypted S3 bucket for state. `use_lockfile = true` enables native S3 state locking in current Terraform.

## Kubernetes

Set a real image in `k8s/deployment.yaml`, create the runtime secret, then apply:

```bash
kubectl create secret generic devops-task-secrets --from-literal=APP_VERSION=1.0.0 --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f k8s/config.yaml -f k8s/deployment.yaml -f k8s/ingress.yaml
kubectl rollout status deployment/devops-task
kubectl port-forward service/devops-task 8080:80
kubectl set image deployment/devops-task app=ghcr.io/OWNER/REPOSITORY:sha-NEW
kubectl rollout status deployment/devops-task
kubectl rollout undo deployment/devops-task
```

The Deployment has two replicas, zero unavailable rolling updates, probes, resource requests/limits, non-root/read-only filesystem controls, and an HPA targeting 70% CPU. The Ingress assumes nginx; port-forward is the local alternative. On EKS, use an AWS Load Balancer Controller, Secrets Manager via External Secrets, managed node autoscaling, and IRSA.

## Observability

```bash
export GRAFANA_ADMIN_PASSWORD='choose-a-local-password'
docker compose -f docker-compose.monitoring.yml up --build
```

Only Grafana is published on `http://localhost:3000`; the other five components use an internal network. Grafana provisions Prometheus and Loki plus Application, Host, and Containers dashboards from repository files. Prometheus retains 15 days; Loki retains 7 days. Alloy discovers Docker containers and parses the JSON `level` field while keeping labels low-cardinality (container, job, level). Node Exporter and cAdvisor use read-only host mounts; cAdvisor is privileged to read cgroups. Alerts cover app down (2m), error rate above 5% (10m), disk above 80% (15m), and container memory above 90% (10m). To investigate an error spike, select the same time window in the Application dashboard, filter Loki by `level`, and correlate log timestamps/endpoints with Prometheus error and latency panels.

## Health automation

```bash
chmod +x scripts/system_health.sh
scripts/system_health.sh --disk 80 --cpu 90 --mem 85
scripts/system_health.sh --json --log /var/log/devops/health_log.txt
```

The script records CPU, memory, all mounted filesystems, load average, and top memory processes; rotates at 1 MiB, emits warnings, and returns 0 healthy, 1 warning, or 2 critical/invalid input. `scripts/system_health.cron` runs it every five minutes.

## Architecture

```text
Commit -> GitHub Actions (lint/test/coverage/Hadolint/ShellCheck/Trivy)
       -> Amazon ECR (SHA + semver, multi-arch, ap-south-1) -> SSM -> EC2 Docker -> smoke test -> rollback
       -> local Kubernetes Deployment (2 replicas, Service, Ingress, HPA)
App /metrics -> Prometheus -> Grafana dashboards/alerts
Docker JSON logs -> Alloy (JSON parsing) -> Loki -> Grafana logs panel
Host -> Node Exporter; containers -> cAdvisor; both -> Prometheus -> Grafana
```

## Design and security decisions

Alpine keeps the final image small while retaining a practical Node runtime; it is multi-stage, pinned, non-root, and Kubernetes runs read-only. EC2 is intentionally simple for the assessment; ECS reduces host operations, while EKS is appropriate when Kubernetes portability justifies its cost. SHA tags are immutable release references. Secrets belong in GitHub/OIDC, AWS Secrets Manager/SSM, or Kubernetes external secrets. Only Grafana is exposed in the monitoring network, IAM is scoped, and Trivy blocks critical findings.

Approximate production cost is $8–$15/month for a free-tier-sized EC2 instance plus modest CloudWatch and S3 state; region, traffic, storage, and free-tier eligibility change this estimate. Destroy test resources after evidence collection.

## What I would improve

Add an AWS OIDC role module and account-specific deployment action, signing/SBOM verification, Alertmanager routing, managed retention sizing, load tests, and a Helm chart. AI tools helped inspect the requirements and draft repetitive configuration; every submitted component was reviewed and locally validated.
