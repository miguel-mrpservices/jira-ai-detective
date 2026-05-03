import json
import boto3
import base64
import urllib3
import re
import os
from datetime import datetime, timedelta

# Initialize AWS clients for the Frankfurt region
bedrock = boto3.client(service_name='bedrock-runtime', region_name='eu-central-1')
logs_client = boto3.client(service_name='logs', region_name='eu-central-1')

# --- CONFIGURATION VARIABLES (from env) ---
MODEL_ID = 'arn:aws:bedrock:eu-central-1:289140051486:inference-profile/eu.anthropic.claude-sonnet-4-6'
JIRA_SITE = os.environ.get('JIRA_SITE')
JIRA_EMAIL = os.environ.get('JIRA_EMAIL')
JIRA_API_TOKEN = os.environ.get('JIRA_API_TOKEN')
WEBHOOK_SECRET_TOKEN = os.environ.get('WEBHOOK_SECRET_TOKEN')

def find_client_log_group(jira_summary, reporter_email, existing_groups):
    prompt = f"""
    Human: I need to find the AWS Log Group for this incident.
    Ticket Title: "{jira_summary}"
    Reporter Email: "{reporter_email}"
    
    Available AWS Log Groups: {json.dumps(existing_groups)}

    Task: Identify which Log Group most likely belongs to this client. 
    Even if the name isn't identical (e.g., "Tecnovachet Sp. z o.o." vs "clients/tecnovachet"), 
    use your judgment to pick the best match from the list.
    Respond ONLY with the exact name from the list. If no match is possible, respond "NONE".
    Assistant:"""
    
    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 50,
        "messages": [{"role": "user", "content": [{"type": "text", "text": prompt}]}]
    })
    
    response = bedrock.invoke_model(modelId=MODEL_ID, body=body)
    return json.loads(response.get('body').read())['content'][0]['text'].strip()

def get_recent_logs(log_group, start_time, end_time):
    try:
        start_ts = int(start_time.timestamp() * 1000)
        end_ts = int(end_time.timestamp() * 1000)
        
        response = logs_client.filter_log_events(
            logGroupName=log_group,
            startTime=start_ts,
            endTime=end_ts,
            limit=50
        )
        events = response.get('events', [])
        
        if not events:
            return "No technical logs found in this timeframe."
            
        return "\n".join([e['message'] for e in events])
    except Exception as e:
        print(f"Error fetching logs from {log_group}: {e}")
        return "Could not retrieve logs due to an access or configuration error."

def post_to_jira(issue_key, text, is_internal=False):
    url = f"https://{JIRA_SITE}/rest/api/3/issue/{issue_key}/comment"
    
    auth_str = f"{JIRA_EMAIL}:{JIRA_API_TOKEN}"
    encoded_auth = base64.b64encode(auth_str.encode()).decode()
    
    content_blocks = []
    for line in text.split('\n'):
        line = line.strip()
        if not line:
            continue
            
        # Detect Subtitles (###)
        if line.startswith('### '):
            content_blocks.append({
                "type": "heading",
                "attrs": {"level": 3},
                "content": [{"type": "text", "text": line.replace('### ', '').strip()}]
            })
        # Detect Bold in an entire line (**Text**)
        elif line.startswith('**') and line.endswith('**'):
            content_blocks.append({
                "type": "paragraph",
                "content": [{
                    "type": "text", 
                    "text": line.replace('**', '').strip(), 
                    "marks": [{"type": "strong"}]
                }]
            })
        # Normal paragraph
        else:
            content_blocks.append({
                "type": "paragraph",
                "content": [{"type": "text", "text": line}]
            })

    if not content_blocks:
        content_blocks = [{"type": "paragraph", "content": [{"type": "text", "text": text}]}]

    payload = {
        "body": {
            "type": "doc",
            "version": 1,
            "content": content_blocks
        }
    }
    
    if is_internal:
        payload["properties"] = [{"key": "sd.public.comment", "value": {"internal": True}}]

    http = urllib3.PoolManager()
    headers = {
        "Authorization": f"Basic {encoded_auth}",
        "Content-Type": "application/json"
    }
    
    response = http.request("POST", url, body=json.dumps(payload), headers=headers)
    return response.status

def lambda_handler(event, context):
    params = event.get('queryStringParameters') or {}
    # CORRECCIÓN AQUÍ: Se cambió SECRET_TOKEN por WEBHOOK_SECRET_TOKEN
    if params.get('token') != WEBHOOK_SECRET_TOKEN:
        return {'statusCode': 403, 'body': 'Forbidden'}

    try:
        data = json.loads(event['body'])
        issue_key = data.get('issue', {}).get('key', 'UNK-000')
        fields = data.get('issue', {}).get('fields', {})
        
        summary = fields.get('summary', 'No summary')
        description = fields.get('description', 'No description')
        reporter_email = fields.get('reporter', {}).get('emailAddress', 'unknown@domain.com')

        incident_time = datetime.utcnow()
        search_start = incident_time - timedelta(hours=2)

        log_groups_resp = logs_client.describe_log_groups(logGroupNamePrefix='clients/')
        all_groups = [g['logGroupName'] for g in log_groups_resp.get('logGroups', [])]

        matched_group = find_client_log_group(summary, reporter_email, all_groups)
        
        app_logs = "No log group matched this client."
        if matched_group != "NONE" and matched_group in all_groups:
            app_logs = get_recent_logs(matched_group, search_start, incident_time)

        # AI Analysis with strict formatting and styling instructions
        final_prompt = f"""
        Human: Act as a Senior DevOps Engineer. Analyze this incident based on the customer report and the actual server logs.
        
        TICKET: {summary}
        DESCRIPTION: {description}
        LOGS (Last 2 hours from {matched_group}): 
        {app_logs}
        
        Provide your response wrapped in XML tags exactly as follows. DO NOT include any other text outside the tags.

        <internal>
        ### 🔍 SUMMARY
        (Max 2 lines. Briefly summarize the issue and state whether technical logs were found).
        
        ### ⚙️ ROOT CAUSE / HYPOTHESIS
        (If logs are present, explain the exact root cause. IF NO LOGS ARE FOUND, explicitly state "No related logs were found" and provide your best technical hypothesis of what might be failing based solely on the ticket description).
        
        ### 🛠️ ACTION PLAN
        (Technical steps to resolve the issue, or investigation steps to confirm your hypothesis if logs were missing).
        </internal>
        
        <public>
        (Draft a brief, polite response to the customer. 
        1. Acknowledge their specific issue based ONLY on the TICKET summary. 
        2. State that our support team has received the report and is actively investigating it.
        
        CRITICAL RULES: 
        - DO NOT reveal the root cause, DO NOT mention the server logs, and DO NOT provide technical explanations or fix steps.
        - STYLE: Use simple, professional business English. DO NOT use em-dashes (—) or hyphens to connect sentences. Use standard periods and commas only.)
        </public>
        
        Assistant:"""

        body = json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 1200,
            "messages": [{"role": "user", "content": [{"type": "text", "text": final_prompt}]}]
        })
        
        ai_resp = bedrock.invoke_model(modelId=MODEL_ID, body=body)
        ai_text = json.loads(ai_resp.get('body').read())['content'][0]['text']

        # Extract content using Regex
        internal_match = re.search(r'<internal>(.*?)</internal>', ai_text, re.DOTALL)
        public_match = re.search(r'<public>(.*?)</public>', ai_text, re.DOTALL)

        internal_note = internal_match.group(1).strip() if internal_match else "Could not generate technical analysis."
        public_note = public_match.group(1).strip() if public_match else "Thank you for reaching out. Our team is currently reviewing your request."

        # publish the message to the client first and then the internal note
        status_pub = post_to_jira(issue_key, public_note, is_internal=False)
        status_int = post_to_jira(issue_key, internal_note, is_internal=True)

        print(f"Posted to Jira. Public HTTP: {status_pub}, Internal HTTP: {status_int}")

        return {'statusCode': 200, 'body': json.dumps('Workflow completed successfully')}

    except Exception as e:
        print(f"Critical execution error: {str(e)}")
        return {'statusCode': 500, 'body': 'Internal Server Error'}