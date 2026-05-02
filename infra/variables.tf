variable "tags" {
  description = "Default tags for all the resources"
  type        = map(string)
  default = {
    Project     = "jira-ai-detective"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment."
  type        = string
  default     = "eu-central-1"
}



variable "jira_site" {
  description = "The Atlassian domain for the Jira instance (e.g., company.atlassian.net)."
  type        = string
}

variable "jira_email" {
  description = "The email address associated with the Jira API token."
  type        = string
}

variable "jira_api_token" {
  description = "API token used for Jira authentication. Marked sensitive to prevent logging."
  type        = string
  sensitive   = true
}

variable "webhook_secret_token" {
  description = "Expected query parameter token for the Lambda Function URL to authorize incoming Jira webhooks."
  type        = string
  sensitive   = true
}