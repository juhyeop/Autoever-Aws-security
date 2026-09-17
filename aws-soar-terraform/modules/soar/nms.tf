###############################################################################
# NMS — CPU/Mem 임계치 알람 + SNS (프로젝트 목표 2번)
#
# CPU는 EC2가 기본 제공하는 AWS/EC2 CPUUtilization,
# 메모리는 CloudWatch Agent가 올리는 CWAgent mem_used_percent 를 씁니다.
# 임계치 80% / 5분 연속은 설계문서와 2-advanced.pdf 실습 기준 그대로입니다.
###############################################################################

resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"

  tags = {
    Name = "${var.name_prefix}-alerts"
  }
}

# EventBridge(자동조치 결과)가 이 토픽에 publish할 수 있게 허용합니다.
data "aws_iam_policy_document" "alerts_topic" {
  statement {
    sid    = "AllowEventBridgePublish"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid    = "AllowCloudWatchAlarmPublish"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid    = "AllowAccountPublish"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}

# apply 후 이 주소로 오는 확인 메일을 눌러야 알림이 도착합니다.
resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == null ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

###############################################################################
# 인스턴스별 CPU / Mem 알람
###############################################################################

resource "aws_cloudwatch_metric_alarm" "cpu" {
  for_each = var.monitored_instance_ids

  alarm_name          = "${var.name_prefix}-${each.key}-cpu-high"
  alarm_description   = "${each.key} CPU 사용률이 ${var.cpu_threshold}% 를 넘었습니다."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = var.cpu_threshold
  comparison_operator = "GreaterThanThreshold"
  # 지표가 잠깐 비어도 알람이 오작동하지 않게.
  treat_missing_data = "notBreaching"

  dimensions = {
    InstanceId = each.value
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.name_prefix}-${each.key}-cpu-high"
  }
}

resource "aws_cloudwatch_metric_alarm" "memory" {
  for_each = var.monitored_instance_ids

  alarm_name          = "${var.name_prefix}-${each.key}-mem-high"
  alarm_description   = "${each.key} 메모리 사용률이 ${var.mem_threshold}% 를 넘었습니다. (CloudWatch Agent 필요)"
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = var.mem_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = each.value
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.name_prefix}-${each.key}-mem-high"
  }
}

###############################################################################
# CloudWatch 대시보드 — 콘솔에서 한눈에 보는 용도
# (Flask 대시보드와 별개로, 지표 원본을 빠르게 확인할 때 씁니다.)
###############################################################################

resource "aws_cloudwatch_dashboard" "nms" {
  dashboard_name = "${var.name_prefix}-nms"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "CPU 사용률 (%)"
          region  = data.aws_region.current.region
          stat    = "Average"
          period  = 60
          view    = "timeSeries"
          stacked = false
          yAxis   = { left = { min = 0, max = 100 } }
          metrics = [
            for key, id in var.monitored_instance_ids :
            ["AWS/EC2", "CPUUtilization", "InstanceId", id, { label = key }]
          ]
          annotations = {
            horizontal = [{ label = "임계치", value = var.cpu_threshold }]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "메모리 사용률 (%)"
          region  = data.aws_region.current.region
          stat    = "Average"
          period  = 60
          view    = "timeSeries"
          stacked = false
          yAxis   = { left = { min = 0, max = 100 } }
          metrics = [
            for key, id in var.monitored_instance_ids :
            ["CWAgent", "mem_used_percent", "InstanceId", id, { label = key }]
          ]
          annotations = {
            horizontal = [{ label = "임계치", value = var.mem_threshold }]
          }
        }
      },
    ]
  })
}
