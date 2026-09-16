resource "aws_codepipeline" "service" {
  for_each = var.services
  name     = "${var.project_name}-${each.key}-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = var.codestar_connection_arn
        FullRepositoryId = var.github_repo
        BranchName       = var.github_branch
        # Only trigger this service's pipeline when its own folder changes
        DetectChanges = "true"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.service[each.key].name
      }
    }
  }

  stage {
    name = "Deploy"

    dynamic "action" {
      for_each = each.value.path_pattern != "" ? [1] : []
      content {
        name            = "Deploy"
        category        = "Deploy"
        owner           = "AWS"
        provider        = "CodeDeployToECS"
        version         = "1"
        input_artifacts = ["build_output"]

        configuration = {
          ApplicationName                = aws_codedeploy_app.service[each.key].name
          DeploymentGroupName            = aws_codedeploy_deployment_group.service[each.key].deployment_group_name
          TaskDefinitionTemplateArtifact = "build_output"
          TaskDefinitionTemplatePath     = "taskdef.json"
          AppSpecTemplateArtifact        = "build_output"
          AppSpecTemplatePath            = "appspec.yml"
        }
      }
    }

    # Internal service (no ALB / no blue-green): deploy via a direct
    # "update ECS service to new task def" ECS deploy action instead.
    dynamic "action" {
      for_each = each.value.path_pattern == "" ? [1] : []
      content {
        name            = "Deploy"
        category        = "Deploy"
        owner           = "AWS"
        provider        = "ECS"
        version         = "1"
        input_artifacts = ["build_output"]

        configuration = {
          ClusterName = aws_ecs_cluster.main.name
          ServiceName = aws_ecs_service.service[each.key].name
          FileName    = "imagedefinitions.json"
        }
      }
    }
  }

  tags = var.tags
}
