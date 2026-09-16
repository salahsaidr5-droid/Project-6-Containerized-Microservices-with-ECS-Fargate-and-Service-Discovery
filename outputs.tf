output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecr_repository_urls" {
  value = { for k, v in aws_ecr_repository.service : k => v.repository_url }
}

output "ecs_execution_role_arn" {
  value = aws_iam_role.ecs_execution.arn
}

output "ecs_task_role_arns" {
  value = { for k, v in aws_iam_role.ecs_task : k => v.arn }
}

output "cloudmap_namespace" {
  value = aws_service_discovery_private_dns_namespace.internal.name
}

output "redis_endpoint" {
  value = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "rds_endpoints" {
  value = { for k, v in aws_db_instance.service : k => v.address }
}

output "codepipeline_names" {
  value = { for k, v in aws_codepipeline.service : k => v.name }
}
