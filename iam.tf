data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------- ECS Task Execution Role (pulls image, writes logs, reads secrets) ----------------
data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${var.project_name}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Execution role also needs to read the specific secrets it injects at launch
data "aws_iam_policy_document" "ecs_execution_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = concat(
      [for s in aws_secretsmanager_secret.db : s.arn],
      [for s in aws_secretsmanager_secret.app : s.arn]
    )
  }
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name   = "${var.project_name}-execution-secrets-access"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.ecs_execution_secrets.json
}

# ---------------- ECS Task Role (what the APP CODE itself can call) - one per service ----------------
resource "aws_iam_role" "ecs_task" {
  for_each           = var.services
  name               = "${var.project_name}-${each.key}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
  tags               = var.tags
}

# Minimal baseline: X-Ray tracing + Cloud Map + CloudWatch logs for every service
data "aws_iam_policy_document" "task_baseline" {
  statement {
    sid = "XRay"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.project_name}-*"]
  }
}

resource "aws_iam_role_policy" "task_baseline" {
  for_each = aws_iam_role.ecs_task
  name     = "${var.project_name}-${each.key}-baseline"
  role     = each.value.id
  policy   = data.aws_iam_policy_document.task_baseline.json
}

# Auth + Orders tasks additionally need access to ElastiCache (implicit via SG,
# no IAM needed for Redis) and their own Secrets Manager secret for direct reads
# if the app fetches at runtime rather than relying solely on injected env vars.
data "aws_iam_policy_document" "task_secrets_read" {
  for_each = toset(["auth", "orders"])
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db[each.key].arn, aws_secretsmanager_secret.app[each.key].arn]
  }
}

resource "aws_iam_role_policy" "task_secrets_read" {
  for_each = data.aws_iam_policy_document.task_secrets_read
  name     = "${var.project_name}-${each.key}-secrets-read"
  role     = aws_iam_role.ecs_task[each.key].id
  policy   = each.value.json
}

# ---------------- CodeBuild role ----------------
resource "aws_iam_role" "codebuild" {
  name = "${var.project_name}-codebuild-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${var.project_name}-codebuild-policy"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:GetBucketLocation"]
        Resource = ["${aws_s3_bucket.artifacts.arn}", "${aws_s3_bucket.artifacts.arn}/*"]
      },
    ]
  })
}

# ---------------- CodePipeline role ----------------
resource "aws_iam_role" "codepipeline" {
  name = "${var.project_name}-codepipeline-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "${var.project_name}-codepipeline-policy"
  role = aws_iam_role.codepipeline.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:GetBucketVersioning"]
        Resource = ["${aws_s3_bucket.artifacts.arn}", "${aws_s3_bucket.artifacts.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection"]
        Resource = var.codestar_connection_arn
      },
      {
        Effect   = "Allow"
        Action   = ["codebuild:BatchGetBuilds", "codebuild:StartBuild"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:GetApplicationRevision",
          "codedeploy:RegisterApplicationRevision",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ecs:DescribeServices", "ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "*"
      },
    ]
  })
}

# ---------------- CodeDeploy role ----------------
resource "aws_iam_role" "codedeploy" {
  name = "${var.project_name}-codedeploy-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "codedeploy_managed" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}
