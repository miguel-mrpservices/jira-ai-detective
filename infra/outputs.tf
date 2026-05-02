output "jira_webhook_url" {
  description = "Copy this URL and paste it into Jira Webhook settings"
  # We join the URL of the Lambda with the value of the variable
  value     = "${aws_lambda_function_url.agent_url.function_url}?token=${var.webhook_secret_token}"
  sensitive = true
}

# AWS Region output for easy script configuration
output "aws_region" {
  description = "Target AWS region. Use this value when prompted by the CloudWatch agent setup script."
  value       = var.aws_region
}

# Outputs for keys are defined in iam.tf!! #