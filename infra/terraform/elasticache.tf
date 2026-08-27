# ── ElastiCache Redis (private, no public exposure) ─────────────────────────

resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.name_prefix}-redis-subnet"
  subnet_ids = aws_subnet.data[*].id
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${local.name_prefix}-redis"
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = var.redis_num_cache_nodes
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.redis.id]
  apply_immediately    = false

  tags = { Name = "${local.name_prefix}-redis" }
}

# ElastiCache (classic) primary endpoint; used by the app as REDIS_URL /
# Celery broker & result backend (Redis DB index picks logical DB).
locals {
  redis_endpoint = aws_elasticache_cluster.redis.cache_nodes[0].address
}