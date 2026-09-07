# deploy/terraform/aws/alb_alarms.tf
# ALB CloudWatch alarms + notification topic (SOC 2 "infrastructure performance
# monitored": errors, latency and unhealthy targets on the public entrypoint).
#
# The ALB is created by the AWS Load Balancer Controller from the chart's
# Ingress, not by Terraform, so it and its target groups are discovered by the
# tags the controller stamps on them. Only wired up when a custom domain is
# set, mirroring data.aws_lb.ingress in dns.tf.

locals {
  alb_monitoring_enabled = var.domain != ""

  # One target group per Ingress backend. The controller tags each with
  # ingress.k8s.aws/resource = "<namespace>/<ingress>-<service>:<port>".
  alb_target_groups = {
    rest = "${local.namespace}/traceroot-traceroot-rest:8000"
    web  = "${local.namespace}/traceroot-traceroot-web:3000"
  }
}

data "aws_lb_target_group" "ingress" {
  for_each = local.alb_monitoring_enabled ? local.alb_target_groups : {}

  tags = {
    "elbv2.k8s.aws/cluster"    = var.name
    "ingress.k8s.aws/resource" = each.value
  }

  depends_on = [helm_release.traceroot]
}

resource "aws_sns_topic" "alb_alarms" {
  count = local.alb_monitoring_enabled ? 1 : 0
  name  = "${var.name}-alb-alarms"
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  count               = local.alb_monitoring_enabled ? 1 : 0
  alarm_name          = "${var.name}-alb-5xx-high"
  alarm_description   = "ALB ${data.aws_lb.ingress[0].name} returned more than 10 5xx responses (ELB-generated) in 5 minutes."
  comparison_operator = "GreaterThanThreshold"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  evaluation_periods  = 1
  dimensions          = { LoadBalancer = data.aws_lb.ingress[0].arn_suffix }
  alarm_actions       = [aws_sns_topic.alb_alarms[0].arn]
  ok_actions          = [aws_sns_topic.alb_alarms[0].arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  count               = local.alb_monitoring_enabled ? 1 : 0
  alarm_name          = "${var.name}-alb-target-5xx-high"
  alarm_description   = "Targets behind ALB ${data.aws_lb.ingress[0].name} returned more than 10 5xx responses in 5 minutes."
  comparison_operator = "GreaterThanThreshold"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  evaluation_periods  = 1
  dimensions          = { LoadBalancer = data.aws_lb.ingress[0].arn_suffix }
  alarm_actions       = [aws_sns_topic.alb_alarms[0].arn]
  ok_actions          = [aws_sns_topic.alb_alarms[0].arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  count               = local.alb_monitoring_enabled ? 1 : 0
  alarm_name          = "${var.name}-alb-latency-high"
  alarm_description   = "ALB ${data.aws_lb.ingress[0].name} p99 target response time above 5 seconds for 15 minutes."
  comparison_operator = "GreaterThanThreshold"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  extended_statistic  = "p99"
  threshold           = 5
  evaluation_periods  = 3
  dimensions          = { LoadBalancer = data.aws_lb.ingress[0].arn_suffix }
  alarm_actions       = [aws_sns_topic.alb_alarms[0].arn]
  ok_actions          = [aws_sns_topic.alb_alarms[0].arn]
  treat_missing_data  = "notBreaching"
}

# UnHealthyHostCount is only published per target group, so one alarm each.
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  for_each            = data.aws_lb_target_group.ingress
  alarm_name          = "${var.name}-alb-${each.key}-unhealthy-hosts"
  alarm_description   = "ALB ${data.aws_lb.ingress[0].name} has at least one unhealthy ${each.key} target for 10 minutes."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1
  evaluation_periods  = 2
  dimensions = {
    LoadBalancer = data.aws_lb.ingress[0].arn_suffix
    TargetGroup  = each.value.arn_suffix
  }
  alarm_actions      = [aws_sns_topic.alb_alarms[0].arn]
  ok_actions         = [aws_sns_topic.alb_alarms[0].arn]
  treat_missing_data = "notBreaching"
}
