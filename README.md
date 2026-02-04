# Azure Function - VM 자동 시작

매일 20시(저녁 8시)에 shutdown된 Azure VM을 자동으로 시작하는 Azure Function입니다.

## 요구사항

- Python 3.12 (LTS)
- Azure Functions Core Tools
- Azure 구독 및 VM 리소스

## 프로젝트 구조

```
function-auto-start/
├── .gitignore
├── .funcignore
├── host.json                 # Azure Functions 호스트 설정
├── requirements.txt          # Python 패키지 의존성
├── local.settings.json       # 로컬 개발 환경 설정 (git에 포함하지 않음)
├── function_app.py          # Function 앱 진입점
└── start_vm/
    └── __init__.py          # Timer Trigger Function 구현
```

## 설정

### 1. 로컬 개발 환경 설정

```bash
# 가상 환경 생성 및 활성화
python3.12 -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate

# 패키지 설치
pip install -r requirements.txt
```

### 2. 환경 변수 설정

`local.settings.json.example`을 참고하여 `local.settings.json` 파일을 생성하세요:

**여러 VM 설정 (권장):**
```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "AZURE_SUBSCRIPTION_ID": "your-subscription-id",
    "AZURE_VM_LIST": "[{\"name\": \"vm-name-1\", \"resource_group\": \"rg-name-1\"}, {\"name\": \"vm-name-2\", \"resource_group\": \"rg-name-2\"}]"
  }
}
```

**단일 VM 설정 (하위 호환성):**
```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "AZURE_SUBSCRIPTION_ID": "your-subscription-id",
    "AZURE_VM_NAME": "your-vm-name",
    "AZURE_RESOURCE_GROUP": "your-resource-group-name"
  }
}
```

**인증 방법:**

#### 옵션 1: Managed Identity (프로덕션 권장)
Azure Function App에 Managed Identity를 할당하고, VM 리소스에 대한 권한을 부여합니다.

#### 옵션 2: Service Principal (로컬 개발)
```json
{
  "AZURE_TENANT_ID": "your-tenant-id",
  "AZURE_CLIENT_ID": "your-client-id",
  "AZURE_CLIENT_SECRET": "your-client-secret"
}
```

#### 옵션 3: Azure CLI (로컬 개발)
```bash
az login
```

### 3. VM 추가하는 방법

매일 자동으로 시작할 VM을 추가하거나 변경하려면 `AZURE_VM_LIST`에 VM 정보를 넣으면 됩니다.

#### VM 목록 형식

각 VM은 `name`(VM 이름)과 `resource_group`(리소스 그룹) 두 필드로 정의합니다.

```json
[
  {"name": "vm-이름-1", "resource_group": "리소스그룹-이름-1"},
  {"name": "vm-이름-2", "resource_group": "리소스그룹-이름-2"}
]
```

#### 새 VM 추가 절차

**1. VM 이름과 리소스 그룹 확인**

```bash
# 구독 내 VM 목록 확인
az vm list --output table

# 특정 리소스 그룹의 VM 확인
az vm list --resource-group <리소스그룹이름> --output table
```

**2. 로컬 설정에 VM 추가 (`local.settings.json`)**

기존 `AZURE_VM_LIST` 배열에 새 객체를 추가합니다.

```json
"AZURE_VM_LIST": "[{\"name\": \"vm-gitlab-kc-01\", \"resource_group\": \"rg-common-gitlab-cjs-kc-01\"}, {\"name\": \"vm-새VM이름\", \"resource_group\": \"rg-새리소스그룹\"}]"
```

**3. Azure Function App 환경 변수에 반영**

```bash
# 기존 VM 목록에 새 VM을 포함한 JSON으로 한 번에 설정
az functionapp config appsettings set \
  --name <function-app-name> \
  --resource-group <resource-group-name> \
  --settings AZURE_VM_LIST='[{"name": "vm-gitlab-kc-01", "resource_group": "rg-common-gitlab-cjs-kc-01"}, {"name": "vm-새VM이름", "resource_group": "rg-새리소스그룹"}]'
```

**4. Managed Identity에 새 VM 권한 부여**

Function App이 Managed Identity를 쓰는 경우, 새 VM에 대한 권한을 추가합니다.

```bash
# Function App의 Managed Identity Principal ID 확인
PRINCIPAL_ID=$(az functionapp identity show \
  --name <function-app-name> \
  --resource-group <resource-group-name> \
  --query principalId -o tsv)

# 새 VM에 Virtual Machine Contributor 역할 부여
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Virtual Machine Contributor" \
  --scope /subscriptions/<subscription-id>/resourceGroups/<vm-리소스그룹>/providers/Microsoft.Compute/virtualMachines/<vm-이름>
```

**5. (선택) 코드 변경 없이 재배포**

환경 변수만 바꿨다면 Function App 재시작으로 적용됩니다. 코드를 수정했다면 배포 후 적용됩니다.

```bash
# Function App 재시작 (환경 변수 적용)
az functionapp restart --name <function-app-name> --resource-group <resource-group-name>
```

#### VM 제거 방법

`AZURE_VM_LIST`에서 해당 VM 객체를 삭제한 뒤, 위와 같이 `az functionapp config appsettings set`로 `AZURE_VM_LIST`를 다시 설정하면 됩니다. 권한(`az role assignment`)은 제거하지 않아도 동작에는 영향이 없습니다.

## 로컬 실행

```bash
# Azure Functions Core Tools 설치 필요
func start
```

## 배포

### Azure Function App 생성

```bash
# 리소스 그룹 생성
az group create --name <resource-group-name> --location <location>

# Storage Account 생성
az storage account create \
  --name <storage-account-name> \
  --resource-group <resource-group-name> \
  --location <location> \
  --sku Standard_LRS

# Function App 생성 (Python 3.12)
az functionapp create \
  --resource-group <resource-group-name> \
  --consumption-plan-location <location> \
  --runtime python \
  --runtime-version 3.12 \
  --functions-version 4 \
  --name <function-app-name> \
  --storage-account <storage-account-name>
```

### Managed Identity 설정

```bash
# System-assigned Managed Identity 활성화
az functionapp identity assign \
  --name <function-app-name> \
  --resource-group <resource-group-name>

# VM 리소스에 대한 권한 부여 (VM Contributor 역할)
az role assignment create \
  --assignee <principal-id> \
  --role "Virtual Machine Contributor" \
  --scope /subscriptions/<subscription-id>/resourceGroups/<vm-resource-group>/providers/Microsoft.Compute/virtualMachines/<vm-name>
```

### 환경 변수 설정

**여러 VM 설정 (권장):**
```bash
az functionapp config appsettings set \
  --name <function-app-name> \
  --resource-group <resource-group-name> \
  --settings \
    AZURE_SUBSCRIPTION_ID=<subscription-id> \
    AZURE_VM_LIST='[{"name": "vm-name-1", "resource_group": "rg-name-1"}, {"name": "vm-name-2", "resource_group": "rg-name-2"}]'
```

**단일 VM 설정:**
```bash
az functionapp config appsettings set \
  --name <function-app-name> \
  --resource-group <resource-group-name> \
  --settings \
    AZURE_SUBSCRIPTION_ID=<subscription-id> \
    AZURE_RESOURCE_GROUP=<vm-resource-group> \
    AZURE_VM_NAME=<vm-name>
```

### 배포

Azure Functions를 배포하는 방법은 여러 가지가 있습니다:

#### 방법 1: Azure Functions Core Tools (권장)

```bash
# 함수 배포
func azure functionapp publish <function-app-name>
```

#### 방법 2: ZIP 배포 (소스 코드 업로드)

소스 코드를 ZIP 파일로 압축하여 직접 업로드하는 방식입니다.

```bash
# 배포 패키지 준비
# .funcignore에 명시된 파일들은 제외됩니다
zip -r function-app.zip . -x "*.git*" -x "*__pycache__*" -x "*.venv*" -x "*local.settings.json"

# Azure CLI를 통한 ZIP 배포
az functionapp deployment source config-zip \
  --resource-group <resource-group-name> \
  --name <function-app-name> \
  --src function-app.zip

# 또는 REST API를 통한 배포
# 1. Publish Profile 가져오기
az functionapp deployment list-publishing-profiles \
  --name <function-app-name> \
  --resource-group <resource-group-name> \
  --xml

# 2. 위에서 얻은 publishUrl과 publishUsername, publishPassword를 사용하여 ZIP 업로드
curl -X POST \
  -u '<publishUsername>:<publishPassword>' \
  --data-binary @function-app.zip \
  https://<function-app-name>.scm.azurewebsites.net/api/zipdeploy
```

#### 방법 3: GitLab CI/CD를 통한 자동 배포

`.gitlab-ci.yml` 파일이 포함되어 있어 GitLab에 코드를 push하면 자동으로 배포됩니다.

**초기 설정:**
1. GitLab 프로젝트 → **Settings → CI/CD → Variables**에서 다음 변수 설정:
   - `AZURE_CLIENT_ID`: Azure Service Principal Client ID
   - `AZURE_CLIENT_SECRET`: Azure Service Principal Client Secret (Masked)
   - `AZURE_TENANT_ID`: Azure Tenant ID
   - `AZURE_SUBSCRIPTION_ID`: Azure 구독 ID

2. Service Principal 생성:
   ```bash
   az ad sp create-for-rbac \
     --name "gitlab-ci-function-deploy" \
     --role contributor \
     --scopes /subscriptions/<subscription-id>/resourceGroups/<resource-group-name>
   ```

**배포 트리거:**
- `develop` 브랜치 push → 개발 환경 자동 배포
- `main` 브랜치 push → 프로덕션 환경 배포 (수동 승인 필요)
- 수동 실행 → 언제든지 수동 배포 가능

자세한 내용은 [GITLAB_CI.md](./GITLAB_CI.md)를 참고하세요.

#### 방법 4: GitHub Actions를 통한 CI/CD

`.github/workflows/deploy.yml` 파일을 생성하여 자동 배포를 설정할 수 있습니다:

```yaml
name: Deploy Azure Function

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.12'
      
      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
      
      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      
      - name: Deploy to Azure Functions
        uses: Azure/functions-action@v1
        with:
          app-name: <function-app-name>
          package: '.'
          publish-profile: ${{ secrets.AZURE_FUNCTIONAPP_PUBLISH_PROFILE }}
```

**GitHub Secrets 설정:**
- `AZURE_CREDENTIALS`: Azure Service Principal 정보 (JSON 형식)
- `AZURE_FUNCTIONAPP_PUBLISH_PROFILE`: Function App의 Publish Profile

#### 방법 5: Azure Portal을 통한 배포

1. Azure Portal에서 Function App 선택
2. **Deployment Center** 메뉴로 이동
3. **Source** 선택 (GitHub, Azure Repos, Local Git 등)
4. 저장소 연결 및 배포 설정

#### 방법 6: VS Code Extension을 통한 배포

1. VS Code에 **Azure Functions** 확장 설치
2. Azure에 로그인
3. Function App 선택 후 **Deploy to Function App** 실행

### 배포 후 확인

```bash
# Function App 상태 확인
az functionapp show \
  --name <function-app-name> \
  --resource-group <resource-group-name>

# 함수 목록 확인
az functionapp function list \
  --name <function-app-name> \
  --resource-group <resource-group-name>
```

## Timer Schedule

현재 설정: `0 0 20 * * *` (매일 20시/저녁 8시)

CRON 표현식 형식: `{second} {minute} {hour} {day} {month} {day-of-week}`

다른 시간으로 변경하려면 `function_app.py`의 `schedule` 파라미터를 수정하세요.

## 로그 확인

```bash
# 실시간 로그 스트리밍
az functionapp log tail --name <function-app-name> --resource-group <resource-group-name>
```

## 문제 해결

### VM 시작 실패
- Managed Identity 또는 Service Principal에 VM 리소스에 대한 적절한 권한이 있는지 확인
- VM 이름, 리소스 그룹 이름, 구독 ID가 정확한지 확인
- `AZURE_VM_LIST` JSON 형식이 올바른지 확인 (각 VM에 대해 `name`과 `resource_group` 필드 필요)

### 인증 오류
- Managed Identity가 활성화되어 있는지 확인
- 로컬 개발 시 Azure CLI 로그인 상태 확인 (`az account show`)

## 라이선스

MIT
