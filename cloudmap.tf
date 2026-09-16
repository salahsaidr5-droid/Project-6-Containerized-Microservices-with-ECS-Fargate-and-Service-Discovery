resource "aws_service_discovery_private_dns_namespace" "internal" {
  name        = "${var.project_name}.local"
  description = "Private DNS namespace for service-to-service discovery"
  vpc         = aws_vpc.main.id
}

resource "aws_service_discovery_service" "service" {
  for_each = var.services
  name     = each.key # resolves as <service>.ecs-microservices.local

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}
