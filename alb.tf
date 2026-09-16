resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = merge(var.tags, { Name = "${var.project_name}-alb" })
}

# One target group PER SERVICE, PER DEPLOYMENT COLOR (blue/green) so CodeDeploy
# can flip the listener between them without downtime.
resource "aws_lb_target_group" "blue" {
  for_each    = { for k, v in var.services : k => v if v.path_pattern != "" }
  name        = "${var.project_name}-${each.key}-blue"
  port        = each.value.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # required for Fargate

  health_check {
    path                = each.value.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }

  deregistration_delay = 30

  tags = merge(var.tags, { Name = "${var.project_name}-${each.key}-blue-tg" })
}

resource "aws_lb_target_group" "green" {
  for_each    = { for k, v in var.services : k => v if v.path_pattern != "" }
  name        = "${var.project_name}-${each.key}-green"
  port        = each.value.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = each.value.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }

  deregistration_delay = 30

  tags = merge(var.tags, { Name = "${var.project_name}-${each.key}-green-tg" })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # Default action: 404 for anything not matched by a path rule below.
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

# Path-based routing rule per public-facing service, pointed at the "blue"
# target group. CodeDeploy manages traffic shifting to "green" during deploys,
# so Terraform only owns the steady-state (blue) wiring here.
resource "aws_lb_listener_rule" "service" {
  for_each     = aws_lb_target_group.blue
  listener_arn = aws_lb_listener.http.arn
  priority     = 100 + index(keys(aws_lb_target_group.blue), each.key)

  action {
    type             = "forward"
    target_group_arn = each.value.arn
  }

  condition {
    path_pattern {
      values = [var.services[each.key].path_pattern]
    }
  }
}
