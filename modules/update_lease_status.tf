module "fan_out_update_lease_status_lambda" {
  source          = "./lambda"
  name            = "fan_out_update_lease_status-${var.namespace}"
  namespace       = var.namespace
  description     = "Initiates the budget check lambda. Invokes a check-budget lamdba for each active lease"
  global_tags     = var.global_tags
  handler         = "fan_out_update_lease_status"
  alarm_topic_arn = aws_sns_topic.alarms_topic.arn

  environment = {
    AWS_CURRENT_REGION                = var.aws_region
    ACCOUNT_DB                        = aws_dynamodb_table.redbox_account.id
    LEASE_DB                          = aws_dynamodb_table.redbox_lease.id
    UPDATE_LEASE_STATUS_FUNCTION_NAME = module.update_lease_status_lambda.name
  }
}

// Allow fan_out_update_lease_status to invoke the update_lease_status lambda
resource "aws_iam_role_policy_attachment" "fan_out_update_lease_status_invoke_lambda" {
  role       = module.fan_out_update_lease_status_lambda.execution_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaRole"
}

module "update_lease_status_lambda" {
  source          = "./lambda"
  name            = "update_lease_status-${var.namespace}"
  namespace       = var.namespace
  description     = "Checks spend for a lease within an AWS account, and locks lease if over budget"
  handler         = "update_lease_status"
  global_tags     = var.global_tags
  alarm_topic_arn = aws_sns_topic.alarms_topic.arn

  environment = {
    AWS_CURRENT_REGION                        = var.aws_region
    ACCOUNT_DB                                = aws_dynamodb_table.redbox_account.id
    LEASE_DB                                  = aws_dynamodb_table.redbox_lease.id
    USAGE_CACHE_DB                            = aws_dynamodb_table.usage_cache.id
    RESET_QUEUE_URL                           = aws_sqs_queue.account_reset.id
    LEASE_LOCKED_TOPIC_ARN                    = aws_sns_topic.lease_locked.arn
    BUDGET_NOTIFICATION_FROM_EMAIL            = var.budget_notification_from_email
    BUDGET_NOTIFICATION_BCC_EMAILS            = join(",", var.budget_notification_bcc_emails)
    BUDGET_NOTIFICATION_TEMPLATE_HTML         = var.budget_notification_template_html
    BUDGET_NOTIFICATION_TEMPLATE_TEXT         = var.budget_notification_template_text
    BUDGET_NOTIFICATION_TEMPLATE_SUBJECT      = var.budget_notification_template_subject
    BUDGET_NOTIFICATION_THRESHOLD_PERCENTILES = join(",", var.budget_notification_threshold_percentiles)
  }
}

// Allow update_lease_status lambda to send emails with SES
resource "aws_iam_role_policy" "check_buget_ses" {
  role   = module.update_lease_status_lambda.execution_role_name
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["ses:SendEmail"],
      "Resource": "*"
    }]
}
POLICY
}

// Run the fan-out-update-lease-status-lambda lambda on a timer (cloudwatch event)
module "dbbackup_lambda_schedule" {
  source              = "./cloudwatch_event"
  name                = "fan_out_update_lease_status-${var.namespace}"
  lambda_function_arn = module.fan_out_update_lease_status_lambda.arn
  schedule_expression = var.update_lease_status_schedule_expression
  description         = "Initiates the update lease status lambda. Invokes an update-lease-statuslamdba for each active lease"
  enabled             = var.update_lease_status_enabled
}