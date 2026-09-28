provider "aws" {
  region     = "eu-west-1"
  access_key = "AKIAEXAMPLEEXAMPLE00"
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_security_group" "db" {
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "settle" {
  engine              = "postgres"
  instance_class      = "db.m5.large"
  allocated_storage   = 100
  username            = "settle"
  password            = "S3ttle-prod-2026"
  publicly_accessible = true
  skip_final_snapshot = true
  vpc_security_group_ids = [aws_security_group.db.id]
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id      = "settle"
  engine          = "redis"
  node_type       = "cache.m5.large"
  num_cache_nodes = 1
}

resource "aws_iam_role_policy" "app" {
  role = "settle-app"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }]
  })
}
