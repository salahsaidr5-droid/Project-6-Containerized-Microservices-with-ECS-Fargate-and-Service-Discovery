resource "aws_db_subnet_group" "data" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private_data[*].id
  tags       = var.tags
}

resource "aws_db_instance" "service" {
  for_each = toset(["auth", "orders"])

  identifier             = "${var.project_name}-${each.key}-db"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  storage_encrypted      = true
  db_name                = "${each.key}db"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.data.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az                = false
  publicly_accessible     = false
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 7

  tags = merge(var.tags, { Name = "${var.project_name}-${each.key}-db" })
}
