###############################################################################
# ALB + WAF (선택) — enable_alb / enable_waf 가 true일 때만
#
# Shield Standard는 ALB에 자동 적용됩니다(별도 리소스 없음).
# 아키텍처 다이어그램의 "Shield Standard 자동적용"이 바로 이 부분입니다.
###############################################################################

resource "aws_lb" "web" {
  count = var.enable_alb ? 1 : 0

  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.alb_subnet_ids

  drop_invalid_header_fields = true

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}

resource "aws_lb_target_group" "web" {
  count = var.enable_alb ? 1 : 0

  name     = "${var.name_prefix}-tg-web"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/"
    matcher             = "200-399"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.name_prefix}-tg-web"
  }
}

resource "aws_lb_target_group_attachment" "web" {
  count = var.enable_alb ? 1 : 0

  target_group_arn = aws_lb_target_group.web[0].arn
  target_id        = aws_instance.web.id
  port             = 80
}

resource "aws_lb_listener" "http" {
  count = var.enable_alb ? 1 : 0

  load_balancer_arn = aws_lb.web[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web[0].arn
  }
}

###############################################################################
# WAFv2 WebACL
###############################################################################

resource "aws_wafv2_web_acl" "this" {
  count = var.enable_alb && var.enable_waf ? 1 : 0

  name        = "${var.name_prefix}-web-acl"
  description = "Managed rules for the DVWA demo target"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # 공통 취약점(SQLi, XSS 등) 관리형 룰셋.
  # ZAP/SQLMap 시연 때 여기서 차단 카운트가 올라가고 Security Hub로도 신호가 갑니다.
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

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.name_prefix}-web-acl"
  }
}

resource "aws_wafv2_web_acl_association" "alb" {
  count = var.enable_alb && var.enable_waf ? 1 : 0

  resource_arn = aws_lb.web[0].arn
  web_acl_arn  = aws_wafv2_web_acl.this[0].arn
}
