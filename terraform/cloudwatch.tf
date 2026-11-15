# ---------- Log groups (the CloudWatch agent on each EC2 ships into these) ----------
resource "aws_cloudwatch_log_group" "app" {
  #checkov:skip=CKV_AWS_338:Lab keeps logs 30 days to control cost
  for_each          = toset(["app", "jenkins", "system"])
  name              = "/${var.project}/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn
}

# ---------- Alerts ----------
resource "aws_sns_topic" "alerts" {
  name              = "${var.project}-alerts"
  kms_master_key_id = aws_kms_key.main.id
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # confirm the subscription email AWS sends you
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each            = aws_instance.node
  alarm_name          = "${var.project}-${each.key}-cpu-high"
  alarm_description   = "CPU above 80% for 10 minutes on ${each.key}"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  dimensions          = { InstanceId = each.value.id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "status_check" {
  for_each            = aws_instance.node
  alarm_name          = "${var.project}-${each.key}-status-check"
  alarm_description   = "EC2 status check failing on ${each.key}"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  dimensions          = { InstanceId = each.value.id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  for_each            = aws_instance.node
  alarm_name          = "${var.project}-${each.key}-memory-high"
  alarm_description   = "Memory above 90% on ${each.key} (from CloudWatch agent)"
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 90
  comparison_operator = "GreaterThanThreshold"
  dimensions          = { InstanceId = each.value.id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

# Count app errors. Container logs are CRI-formatted ("<ts> stderr F {json}") and the app
# only writes errors to stderr, so matching the stream name is the most robust filter.
resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  name           = "${var.project}-app-errors"
  log_group_name = aws_cloudwatch_log_group.app["app"].name
  pattern        = "stderr"
  metric_transformation {
    name      = "AppErrors"
    namespace = "ShipGuard"
    value     = "1"
  }
}

# ---------- Dashboard ----------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = var.project
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title   = "CPU utilization"
          region  = var.aws_region
          stat    = "Average"
          period  = 300
          metrics = [for k, v in aws_instance.node : ["AWS/EC2", "CPUUtilization", "InstanceId", v.id, { label = k }]]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title   = "Memory used % (CloudWatch agent)"
          region  = var.aws_region
          stat    = "Average"
          period  = 300
          metrics = [for k, v in aws_instance.node : ["CWAgent", "mem_used_percent", "InstanceId", v.id, { label = k }]]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title   = "App errors"
          region  = var.aws_region
          stat    = "Sum"
          period  = 300
          metrics = [["ShipGuard", "AppErrors"]]
        }
      },
      {
        type = "log", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "Latest app logs"
          region = var.aws_region
          query  = "SOURCE '${aws_cloudwatch_log_group.app["app"].name}' | fields @timestamp, @message | sort @timestamp desc | limit 50"
          view   = "table"
        }
      }
    ]
  })
}
