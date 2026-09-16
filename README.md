# ECS Fargate Microservices — Terraform

Maps 1:1 to the architecture in the diagram (VPC with public/private-services/
private-data subnets, ALB path routing, ECS Fargate + Cloud Map, Secrets
Manager, ElastiCache Redis, CodePipeline/CodeBuild/CodeDeploy blue-green,
X-Ray sidecar).

## Layout
```
versions.tf, variables.tf          provider + inputs
vpc.tf, security_groups.tf         networking
ecr.tf                             3 ECR repos (scan on push)
secrets.tf                         Secrets Manager (db creds + app secrets)
rds.tf, elasticache.tf             Auth/Orders Postgres + shared Redis
alb.tf                             ALB, blue/green target groups, path rules
cloudmap.tf                        service discovery namespace
iam.tf                             execution role + per-service task roles
ecs.tf                             cluster, task defs (+ X-Ray sidecar), services
artifacts.tf                       S3 bucket for pipeline artifacts
codebuild.tf, codedeploy.tf,
codepipeline.tf                    CI/CD per service
services/<name>/                   Dockerfile, buildspec.yml, taskdef.template.json, appspec.yml
```

## First-time manual steps (can't be done by Terraform alone)
1. **CodeStar Connection to GitHub**: create it once in the console
   (Developer Tools → Settings → Connections → GitHub), approve the OAuth
   install, copy the connection ARN into `terraform.tfvars`.
2. Push a real Dockerfile per service (placeholders are in `services/*/Dockerfile`).
3. `taskdef.template.json` under each service has placeholder role ARNs —
   after your first `terraform apply`, run `terraform output ecs_execution_role_arn`
   and `terraform output ecs_task_role_arns`, then fill those in (or template
   them from a script before commit).

## Deploy
```bash
cp terraform.tfvars.example terraform.tfvars   # fill in real values
terraform init
terraform plan
terraform apply
```

## Notes / things worth knowing before you touch this in prod
- `notifications` has no ALB rule (`path_pattern = ""`) — it's internal-only,
  reachable via Cloud Map at `notifications.ecs-microservices.local`, and
  deploys via plain ECS rolling update rather than CodeDeploy blue/green.
- `auth` and `orders` get blue/green via CodeDeploy + two target groups
  (blue/green) per service; Terraform intentionally stops managing
  `task_definition`/`load_balancer` on the `aws_ecs_service` after first
  apply (`lifecycle.ignore_changes`) so CodeDeploy can own deployments.
- DB password is a plain sensitive variable here for simplicity — swap for
  `random_password` + writing straight to Secrets Manager if you want
  Terraform to never see a real password at all.
- X-Ray daemon runs as a sidecar container in every task def (UDP 2000);
  the app SDK inside each service must be configured to send segments to
  `127.0.0.1:2000` (or `AWS_XRAY_DAEMON_ADDRESS` env var).
- RDS/ElastiCache are single-AZ / single-node to keep this a learning
  build — add `multi_az = true` and Redis replicas for anything real.
