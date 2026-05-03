# Package the Python script into a ZIP file automatically
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../src/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

# IAM execution role for the Lambda function
resource "aws_iam_role" "lambda_exec_role" {
  name = "jira_ai_detective_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# IAM policy for CloudWatch Logs and Bedrock invocation
resource "aws_iam_role_policy" "lambda_permissions" {
  name = "jira_ai_detective_policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Allow reading client logs and writing execution logs
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:FilterLogEvents",
          "logs:DescribeLogGroups"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        # Allow Claude Sonnet invocation
        Action   = "bedrock:InvokeModel"
        Effect   = "Allow"
        Resource = "arn:aws:bedrock:eu-central-1:289140051486:inference-profile/eu.anthropic.claude-sonnet-4-6"
      }
    ]
  })
}

# Core Lambda function definition
resource "aws_lambda_function" "jira_ai_agent" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  function_name = "jira-ai-detective"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30

  # Inject sensitive credentials and config via environment variables
  environment {
    variables = {
      JIRA_SITE            = var.jira_site
      JIRA_EMAIL           = var.jira_email
      JIRA_API_TOKEN       = var.jira_api_token
      WEBHOOK_SECRET_TOKEN = var.webhook_secret_token
    }
  }
}

# Public endpoint for Jira webhook
resource "aws_lambda_function_url" "agent_url" {
  function_name      = aws_lambda_function.jira_ai_agent.function_name
  # Auth is bypassed at the AWS level and handled internally via query parameters
  authorization_type = "NONE"
}

# --- PERMISSIONS TO ALLOW PUBLIC ACCESS ---

#  Explicit permission for the internet to invoke the Lambda URL
resource "aws_lambda_permission" "allow_public_invoke_url" {
  statement_id           = "AllowPublicInvokeViaURL" 
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.jira_ai_agent.arn 
  principal              = "*"
  function_url_auth_type = "NONE"

  depends_on = [
    aws_lambda_function.jira_ai_agent,
    aws_lambda_function_url.agent_url
  ]
}

#  General invoke permission (Required by AWS Console to clear the security warning)
resource "aws_lambda_permission" "allow_public_invoke_general" {
  statement_id  = "AllowPublicInvokeGeneral"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.jira_ai_agent.arn
  principal     = "*"

  depends_on = [
    aws_lambda_function.jira_ai_agent
  ]
}