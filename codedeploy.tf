# Only services with an ALB path (public-facing) get blue/green CodeDeploy.
# "notifications" (internal-only) rolls via plain ECS rolling update instead.

resource "aws_codedeploy_app" "service" {
  for_each         = { for k, v in var.services : k => v if v.path_pattern != "" }
  name             = "${var.project_name}-${each.key}"
  compute_platform = "ECS"
}

resource "aws_codedeploy_deployment_group" "service" {
  for_each               = aws_codedeploy_app.service
  app_name               = each.value.name
  deployment_group_name  = "${var.project_name}-${each.key}-dg"
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  blue_green_deployment_config {
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
  }

  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.main.name
    service_name = aws_ecs_service.service[each.key].name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.http.arn]
      }
      target_group {
        name = aws_lb_target_group.blue[each.key].name
      }
      target_group {
        name = aws_lb_target_group.green[each.key].name
      }
    }
  }
}
