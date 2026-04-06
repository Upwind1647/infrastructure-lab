resource "aws_sns_topic" "budget_alerts" {
  count = var.enable_cost_budget ? 1 : 0

  name = "infrastructure-lab-budget-alerts"

  tags = {
    Name    = "infrastructure-lab-budget-alerts"
    Purpose = "FinOps guardrail alerts"
  }
}

resource "aws_sns_topic_subscription" "budget_email" {
  count = var.enable_cost_budget ? 1 : 0

  topic_arn = aws_sns_topic.budget_alerts[0].arn
  protocol  = "email"
  endpoint  = trimspace(var.budget_alert_email)
}

resource "aws_budgets_budget" "monthly" {
  count = var.enable_cost_budget ? 1 : 0

  name         = var.budget_name
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = var.budget_threshold_warning_percent
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts[0].arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = var.budget_threshold_critical_percent
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts[0].arn]
  }
}
