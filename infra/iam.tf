# IAM User for the client on-premise server
resource "aws_iam_user" "client_tecnovachet" {
  name = "clients-tecnovachet"
  path = "/clients/"
}

# Attach the AWS Managed Policy for CloudWatch Agent
resource "aws_iam_user_policy_attachment" "client_tecnovachet_cw_policy" {
  user       = aws_iam_user.client_tecnovachet.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Access Keys generation for the CloudWatch Agent configuration
resource "aws_iam_access_key" "client_tecnovachet_key" {
  user = aws_iam_user.client_tecnovachet.name
}

# Outputs to retrieve the credentials after deployment
output "tecnovachet_access_key_id" {
  description = "Access Key ID for Tecnovachet on-premise agent."
  value       = aws_iam_access_key.client_tecnovachet_key.id
}

output "tecnovachet_secret_access_key" {
  description = "Secret Access Key for Tecnovachet on-premise agent."
  value       = aws_iam_access_key.client_tecnovachet_key.secret
  sensitive   = true
}