terraform {
  backend "s3" {
    bucket = "mrpservices-tfstates-dev" 
    key    = "jira-ai-detective/terraform.tfstate"   
    region = "eu-central-1"                 
  }
}