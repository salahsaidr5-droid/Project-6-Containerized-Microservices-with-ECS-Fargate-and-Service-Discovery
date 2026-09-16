resource "aws_codebuild_project" "service" {
  for_each      = var.services
  name          = "${var.project_name}-${each.key}-build"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 15

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true # required to build Docker images

    environment_variable {
      name  = "ECR_REPO_URL"
      value = aws_ecr_repository.service[each.key].repository_url
    }
    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }
    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }
    environment_variable {
      name  = "SERVICE_NAME"
      value = each.key
    }
    environment_variable {
      name  = "CONTAINER_PORT"
      value = tostring(each.value.container_port)
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "services/${each.key}/buildspec.yml"
  }

  tags = var.tags
}
