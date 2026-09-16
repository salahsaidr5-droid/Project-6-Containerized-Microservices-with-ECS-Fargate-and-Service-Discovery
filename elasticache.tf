resource "aws_elasticache_subnet_group" "data" {
  name       = "${var.project_name}-redis-subnet-group"
  subnet_ids = aws_subnet.private_data[*].id
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.project_name}-redis"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  port                 = 6379
  parameter_group_name = "default.redis7"
  subnet_group_name    = aws_elasticache_subnet_group.data.name
  security_group_ids   = [aws_security_group.redis.id]

  tags = merge(var.tags, { Name = "${var.project_name}-redis" })
}
