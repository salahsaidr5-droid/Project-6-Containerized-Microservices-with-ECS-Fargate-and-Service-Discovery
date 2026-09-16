resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

resource "aws_cloudwatch_log_group" "service" {
  for_each          = var.services
  name              = "/ecs/${var.project_name}-${each.key}"
  retention_in_days = 14
  tags              = var.tags
}

locals {
  # X-Ray daemon runs as a sidecar in every task, listening on 2000/udp.
  xray_container = {
    name      = "xray-daemon"
    image     = "public.ecr.aws/xray/aws-xray-daemon:latest"
    essential = false
    cpu       = 32
    memory    = 256
    portMappings = [
      { containerPort = 2000, protocol = "udp" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.project_name}-xray"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "xray"
      }
    }
  }
}

resource "aws_cloudwatch_log_group" "xray" {
  name              = "/ecs/${var.project_name}-xray"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_ecs_task_definition" "service" {
  for_each                 = var.services
  family                   = "${var.project_name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task[each.key].arn

  container_definitions = jsonencode([
    {
      name      = each.key
      image     = "${aws_ecr_repository.service[each.key].repository_url}:latest"
      essential = true
      portMappings = [
        { containerPort = each.value.container_port, protocol = "tcp" }
      ]
      environment = [
        { name = "SERVICE_NAME", value = each.key },
        { name = "NODE_ENV", value = var.environment },
        { name = "CLOUDMAP_NAMESPACE", value = aws_service_discovery_private_dns_namespace.internal.name },
        { name = "REDIS_HOST", value = aws_elasticache_cluster.redis.cache_nodes[0].address },
        { name = "REDIS_PORT", value = tostring(aws_elasticache_cluster.redis.cache_nodes[0].port) },
      ]
      secrets = contains(["auth", "orders"], each.key) ? [
        { name = "DB_CREDENTIALS", valueFrom = aws_secretsmanager_secret.db[each.key].arn },
        { name = "APP_SECRETS", valueFrom = aws_secretsmanager_secret.app[each.key].arn },
      ] : [
        { name = "APP_SECRETS", valueFrom = aws_secretsmanager_secret.app[each.key].arn },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.service[each.key].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = each.key
        }
      }
    },
    local.xray_container
  ])

  tags = merge(var.tags, { Name = "${var.project_name}-${each.key}-taskdef" })
}

resource "aws_ecs_service" "service" {
  for_each        = var.services
  name            = "${var.project_name}-${each.key}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.service[each.key].arn
  desired_count   = each.value.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private_app[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  # Public-facing services (path_pattern set) register with the ALB blue target group.
  dynamic "load_balancer" {
    for_each = each.value.path_pattern != "" ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.blue[each.key].arn
      container_name   = each.key
      container_port   = each.value.container_port
    }
  }

  service_registries {
    registry_arn = aws_service_discovery_service.service[each.key].arn
  }

  # CodeDeploy takes over traffic-shifting after the first apply; Terraform
  # should stop fighting it over task_definition/load_balancer post-deploy.
  lifecycle {
    ignore_changes = [task_definition, load_balancer]
  }

  deployment_controller {
    type = each.value.path_pattern != "" ? "CODE_DEPLOY" : "ECS"
  }

  depends_on = [aws_lb_listener.http]

  tags = merge(var.tags, { Name = "${var.project_name}-${each.key}-svc" })
}
