variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project/prefix name used on all resources"
  type        = string
  default     = "ecs-microservices"
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of AZs to spread subnets across"
  type        = number
  default     = 2
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDRs for private subnets running ECS services"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_data_subnet_cidrs" {
  description = "CIDRs for private subnets running RDS/ElastiCache"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "services" {
  description = "Map of microservice configs (auth, orders, notifications)"
  type = map(object({
    container_port = number
    cpu            = number
    memory         = number
    desired_count  = number
    path_pattern   = string # ALB path routing, empty string = no ALB rule (internal only)
    health_check_path = string
  }))
  default = {
    auth = {
      container_port     = 3000
      cpu                = 256
      memory             = 512
      desired_count      = 2
      path_pattern       = "/api/auth/*"
      health_check_path  = "/health"
    }
    orders = {
      container_port     = 3000
      cpu                = 256
      memory             = 512
      desired_count      = 2
      path_pattern       = "/api/orders/*"
      health_check_path  = "/health"
    }
    notifications = {
      container_port     = 3000
      cpu                = 256
      memory             = 512
      desired_count      = 1
      path_pattern       = ""
      health_check_path  = "/health"
    }
  }
}

variable "db_username" {
  description = "Master username for RDS databases"
  type        = string
  default     = "app_admin"
}

variable "db_password" {
  description = "Master password for RDS databases (prefer passing via TF_VAR or a secrets pipeline, never commit this)"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t4g.micro"
}

variable "github_repo" {
  description = "GitHub repo in 'owner/repo' form used by CodePipeline source stage"
  type        = string
  default     = "your-org/your-repo"
}

variable "github_branch" {
  description = "Branch CodePipeline tracks"
  type        = string
  default     = "main"
}

variable "codestar_connection_arn" {
  description = "ARN of an existing CodeStar Connections connection to GitHub (create once manually/via console, then paste here)"
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project = "ecs-microservices"
  }
}
