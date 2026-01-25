# Versa Director REST API Notes - January 2026

## Directors

| Location | IP | SSH User | SSH Password | GUI User | GUI Password |
|----------|-----|----------|--------------|----------|--------------|
| Local (Proxmox) | 192.168.10.51 | admin | Versa@123@@ | Administrator | Versa@123!! |
| Remote (AWS) | 107.22.19.157 | - | - | Administrator | InfobloxHalo@123 |

---

## OAuth Authentication

### Step 1: Create OAuth Client (One-time setup)

```bash
curl -k -X POST 'https://<DIRECTOR_IP>:9182/auth/admin/clients' \
  -H "Content-Type: application/json" \
  -u 'Administrator:<PASSWORD>' \
  -d '{
    "name": "apiClient",
    "enabled": "true",
    "access_token_validity": "31536000",
    "refresh_token_validity": "31536000",
    "allowed_ips": ["0.0.0.0/0"],
    "auto_refresh": "true"
  }'
```

**Response contains:** `client_id` and `client_secret`

### Step 2: Get Access Token

```bash
curl -k -X POST 'https://<DIRECTOR_IP>:9183/auth/token' \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "<CLIENT_ID>",
    "client_secret": "<CLIENT_SECRET>",
    "username": "Administrator",
    "password": "<PASSWORD>",
    "grant_type": "password"
  }'
```

**Response contains:** `access_token` (use this for API calls)

### Step 3: Make API Calls

```bash
curl -k -X GET 'https://<DIRECTOR_IP>:9183/vnms/<endpoint>' \
  -H "Accept: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>"
```

---

## OAuth Clients Created

### Local Director (192.168.10.51)
| Field | Value |
|-------|-------|
| Client ID | E29EC5CD355E6D0A053AAA2E2CFF67A1 |
| Client Secret | 356ed3ea98df9a75e03c5371297ddeca |
| Token Validity | 1 year |

### Remote Director (107.22.19.157)
| Field | Value |
|-------|-------|
| Client ID | 050AF1D52BE4FB3E53EC5FE3EB20A7DC |
| Client Secret | ec6f2aec970857f8e9840905b18d4e44 |
| Token Validity | 1 year |

**Current Token (expires Jan 2027):**
```
eyJhbGciOiJIUzI1NiJ9.eyJqdGkiOiI5YmVkZTdmOTg2OWQ3MTVjYjg5NTMzN2E2NDg4Njc2ZGY1NTgzNDcwY2Q0YTI2Y2Y5NDNkZDZhNDU1NTE5MzEyIiwiaWF0IjoxNzY5MTUyNTczLCJyb2xlIjoiUHJvdmlkZXJEYXRhQ2VudGVyU3lzdGVtQWRtaW4iLCJleHAiOjE4MDA2ODg1NzN9.UbxFOcKF1JC7-vcz76VlxMKSpfvuqurcea60X3pJ2B4
```

---

## Tested API Endpoints

### Organizations
```bash
GET /vnms/organization/orgs
```

### Appliances (requires pagination)
```bash
GET /vnms/appliance/appliance?offset=0&limit=100
```

### Response Example - Appliances
```json
{
  "versanms.ApplianceStatusResult": {
    "totalCount": 2,
    "appliances": [
      {
        "name": "Cont-1",
        "type": "controller",
        "ipAddress": "10.234.3.142",
        "ping-status": "REACHABLE",
        "sync-status": "IN_SYNC",
        "softwareVersion": "22.1.4-GA"
      },
      {
        "name": "Device-test",
        "type": "branch",
        "ipAddress": "172.16.0.5",
        "ping-status": "REACHABLE",
        "sync-status": "IN_SYNC",
        "softwareVersion": "22.1.4-GA"
      }
    ]
  }
}
```

---

## Quick Test Script (Bash)

Save as `versa_api_test.sh`:

```bash
#!/bin/bash
DIRECTOR="107.22.19.157"
TOKEN="eyJhbGciOiJIUzI1NiJ9.eyJqdGkiOiI5YmVkZTdmOTg2OWQ3MTVjYjg5NTMzN2E2NDg4Njc2ZGY1NTgzNDcwY2Q0YTI2Y2Y5NDNkZDZhNDU1NTE5MzEyIiwiaWF0IjoxNzY5MTUyNTczLCJyb2xlIjoiUHJvdmlkZXJEYXRhQ2VudGVyU3lzdGVtQWRtaW4iLCJleHAiOjE4MDA2ODg1NzN9.UbxFOcKF1JC7-vcz76VlxMKSpfvuqurcea60X3pJ2B4"

# Get Organizations
echo "=== Organizations ==="
curl -k -s -X GET "https://${DIRECTOR}:9183/vnms/organization/orgs" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer $TOKEN" | jq .

# Get Appliances
echo "=== Appliances ==="
curl -k -s -X GET "https://${DIRECTOR}:9183/vnms/appliance/appliance?offset=0&limit=100" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer $TOKEN" | jq .
```

---

## PowerShell Version

```powershell
$Director = "107.22.19.157"
$Token = "eyJhbGciOiJIUzI1NiJ9.eyJqdGkiOiI5YmVkZTdmOTg2OWQ3MTVjYjg5NTMzN2E2NDg4Njc2ZGY1NTgzNDcwY2Q0YTI2Y2Y5NDNkZDZhNDU1NTE5MzEyIiwiaWF0IjoxNzY5MTUyNTczLCJyb2xlIjoiUHJvdmlkZXJEYXRhQ2VudGVyU3lzdGVtQWRtaW4iLCJleHAiOjE4MDA2ODg1NzN9.UbxFOcKF1JC7-vcz76VlxMKSpfvuqurcea60X3pJ2B4"

$Headers = @{
    "Accept" = "application/json"
    "Authorization" = "Bearer $Token"
}

# Get Appliances
Invoke-RestMethod -Uri "https://${Director}:9183/vnms/appliance/appliance?offset=0&limit=100" `
  -Headers $Headers -SkipCertificateCheck | ConvertTo-Json -Depth 10
```

---

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| `Connection reset by peer` | Source IP not allowed | Add your IP to OAuth client's allowed_ips via Director UI |
| `client_ip_not_allowed` | Same as above | Same - configure allowed IPs |
| `invalid_token` | Token has line breaks | Paste token on single line, or use variable |
| `Account locked` | Too many failed attempts | Unlock via Director UI: Administration → Users |

### Check Your Public IP
```bash
curl -s ifconfig.me
```

### Ports
| Port | Purpose |
|------|---------|
| 9182 | OAuth Admin (create clients) |
| 9183 | OAuth Token & REST API |
| 443 | Web UI |

---

## Workflow Template API

### List Templates
```bash
GET /vnms/sdwan/workflow/templates?organization=VERSA&offset=0&limit=50
```

### Get Template Details
```bash
GET /vnms/sdwan/workflow/templates/template/<TEMPLATE_NAME>?organization=VERSA
```

### Create Template
```bash
POST /vnms/sdwan/workflow/templates/template?dryRun=false
Content-Type: application/json

{
  "versanms.sdwan-template-workflow": {
    "templateName": "new_template_name",
    "templateType": "sdwan-post-staging",
    "deviceType": "full-mesh",
    "deviceDeployment": "normal",
    "controllers": ["Controller-1"],
    "providerOrg": {"name": "VERSA", "nextGenFW": true},
    "solutionTier": "Premier-Secure-SDWAN",
    "bandwidth": 1000,
    "isAnalyticsEnabled": true,
    ...
  }
}
```

### Deploy Template
```bash
POST /vnms/sdwan/workflow/templates/template/deploy/<TEMPLATE_NAME>?verifyDiff=true
```

### Delete Template
```bash
DELETE /vnms/sdwan/workflow/templates/<TEMPLATE_NAME>
```

---

## Documentation

- Official Docs: https://docs.versa-networks.com/Management_and_Orchestration/Versa_Director/Director_REST_APIs/Versa_Director_REST_API_Overview
- Versa AI-MCP Wiki: https://wiki.versa-networks.com/pages/viewpage.action?pageId=124702398
- MCP Access Request: arunc@versa-networks.com

---

*Last updated: January 23, 2026*
