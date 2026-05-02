# --- CONFIGURATION ---
$clientName = "INTRODUCE CLIENT NAME HERE"
$accessKey  = "INTRODUCE CLIENT ACCESS_KEY HERE"
$secretKey  = "INTRODUCE CLIENT SECRET_ACCESS_KEY HERE"
$region     = "eu-central-1"

# --- INITIAL SETUP ---
# Ensure the base directory exists for the CloudWatch agent configuration
$basePath = "C:\ProgramData\Amazon\AmazonCloudWatchAgent"
if (!(Test-Path $basePath)) { New-Item -ItemType Directory -Path $basePath -Force }

# --- STORE CREDENTIALS IN NEUTRAL ZONE ---
$creds = @"
[default]
aws_access_key_id = $accessKey
aws_secret_access_key = $secretKey
region = $region
"@
Set-Content -Path "$basePath\credentials" -Value $creds -Encoding ASCII

# --- CONFIGURE COMMON-CONFIG ---
# CORRECCIÓN: Uso de comillas simples para la ruta en formato TOML
$commonConfig = @"
[credentials]
    shared_credential_profile = "default"
    shared_credential_file = '$basePath\credentials'
"@
Set-Content -Path "$basePath\common-config.toml" -Value $commonConfig -Encoding ASCII

# --- CREATE LOG CONFIGURATION (config.json) ---
# Dynamic log group name using the $clientName variable
$jsonLogs = @"
{
  "agent": { "region": "$region" },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "C:\\mrpservices\\logs\\*\\*.log",
            "log_group_name": "clients/$clientName",
            "log_stream_name": "node-mrpservices"
          }
        ]
      }
    }
  }
}
"@
$configPath = "C:\Program Files\Amazon\AmazonCloudWatchAgent\config.json"
Set-Content -Path $configPath -Value $jsonLogs -Encoding ASCII

# --- START THE AGENT ---
Set-Location "C:\Program Files\Amazon\AmazonCloudWatchAgent"
.\amazon-cloudwatch-agent-ctl.ps1 -a fetch-config -m onPremise -s -c file:".\config.json"

# --- VERIFICATION ---
& ".\amazon-cloudwatch-agent-ctl.ps1" -m onPremise -a status