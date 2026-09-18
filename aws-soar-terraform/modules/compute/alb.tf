############################################
# ALB + WAFv2 (옵션)
#
# 기획서 트래픽 허용표 ①② : Internet -> ALB -> Nginx(Docker Host)
# WAFv2 는 NLB 에 연결할 수 없습니다. SEC-08(SQL Injection) 시나리오를
# 유지하려면 진입점이 ALB 여야 합니다.
#
# 비용 때문에 enable_alb / enable_waf 는 기본 false 입니다.
# 끈 상태에서는 관리자 IP 에서 Docker Host 로 직접 점검합니다.
############################################

resource "aws_lb" "main" {
  count = var.enable_alb ? 1 : 0

  name               = substr("${var.name_prefix}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.sg_alb_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false
  drop_invalid_header_fields = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb" })
}

resource "aws_lb_target_group" "service" {
  count = var.enable_alb ? 1 : 0

  name        = substr("${var.name_prefix}-svc-tg", 0, 32)
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-svc-tg" })
}

resource "aws_lb_target_group_attachment" "service" {
  count = var.enable_alb ? 1 : 0

  target_group_arn = aws_lb_target_group.service[0].arn
  target_id        = aws_instance.docker_host.id
  port             = 80
}

resource "aws_lb_target_group" "dvwa" {
  count = var.enable_alb && var.enable_dvwa_instance ? 1 : 0

  name        = substr("${var.name_prefix}-dvwa-tg", 0, 32)
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/"
    matcher             = "200,302"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-dvwa-tg" })
}

resource "aws_lb_target_group_attachment" "dvwa" {
  count = var.enable_alb && var.enable_dvwa_instance ? 1 : 0

  target_group_arn = aws_lb_target_group.dvwa[0].arn
  target_id        = aws_instance.web_dvwa[0].id
  port             = 80
}

locals {
  has_certificate = var.acm_certificate_arn != ""
}

# HTTP 리스너
#  - 인증서가 있으면 443 으로 301 리다이렉트 (SEC-02 개선 후 상태)
#  - 인증서가 없으면 그대로 전달 (SEC-02 탐지 대상인 평문 HTTP 상태)
resource "aws_lb_listener" "http" {
  count = var.enable_alb ? 1 : 0

  load_balancer_arn = aws_lb.main[0].arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = local.has_certificate ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = local.has_certificate ? [] : [1]
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.service[0].arn
    }
  }
}

resource "aws_lb_listener" "https" {
  count = var.enable_alb && local.has_certificate ? 1 : 0

  load_balancer_arn = aws_lb.main[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service[0].arn
  }
}

locals {
  primary_listener_arn = var.enable_alb ? (
    local.has_certificate ? aws_lb_listener.https[0].arn : aws_lb_listener.http[0].arn
  ) : ""
}

resource "aws_lb_listener_rule" "dvwa" {
  count = var.enable_alb && var.enable_dvwa_instance ? 1 : 0

  listener_arn = local.primary_listener_arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dvwa[0].arn
  }

  condition {
    path_pattern {
      values = ["/dvwa", "/dvwa/*"]
    }
  }

  tags = merge(var.tags, { Scenario = "SEC-08" })
}

############################################
# WAFv2 (SEC-08)
############################################

resource "aws_wafv2_web_acl" "main" {
  count = var.enable_alb && var.enable_waf ? 1 : 0

  name        = "${var.name_prefix}-web-acl"
  description = "Managed rules for SQLi and common web attacks, plus a rate limit"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "SQLiRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitPerIp"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 500
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitPerIp"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, { Scenario = "SEC-08" })
}

resource "aws_wafv2_web_acl_association" "main" {
  count = var.enable_alb && var.enable_waf ? 1 : 0

  resource_arn = aws_lb.main[0].arn
  web_acl_arn  = aws_wafv2_web_acl.main[0].arn
}
