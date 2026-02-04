# 테스트 가이드

Azure Function의 VM 자동 시작 기능을 테스트하는 방법을 안내합니다.

## 테스트 방법

### 방법 1: 헬스체크 엔드포인트 (가장 간단)

Function App의 상태를 확인하는 헬스체크 엔드포인트입니다. 인증이 필요 없습니다.

**브라우저에서:**
```
https://function-auto-startup.azurewebsites.net/api/health
```

**curl 사용:**
```bash
curl https://function-auto-startup.azurewebsites.net/api/health
```

**예상 응답:**
```json
{
  "status": "healthy",
  "timestamp": "2026-02-04T03:45:00.123456",
  "service": "azure-function-vm-auto-start",
  "version": "1.0.0",
  "runtime": {
    "python_version": "3.12.x",
    "platform": "Linux-x.x.x"
  },
  "environment": {
    "subscription_id": "42f0cf0c-5a7a-4aca-9a9e-31b236b9defa",
    "function_app_name": "function-auto-startup",
    "vm_count": 3
  }
}
```

### 방법 2: HTTP Trigger를 통한 수동 실행 (권장)

배포된 Function App에 HTTP 엔드포인트가 추가되어 있어, 언제든지 수동으로 실행할 수 있습니다.

#### 1. Function Key 가져오기

```bash
# Function Key 조회
az functionapp function keys list \
  --name function-auto-startup \
  --resource-group rg-common-gitlabrunner-kc-01 \
  --function-name StartVMsManual

# 또는 Master Key 사용 (모든 함수에 접근 가능)
az functionapp keys list \
  --name function-auto-startup \
  --resource-group rg-common-gitlabrunner-kc-01
```

#### 2. HTTP 요청 실행

**curl 사용:**
```bash
# Function Key 사용
curl -X POST "https://function-auto-startup.azurewebsites.net/api/start-vms?code=<function-key>"

# Master Key 사용
curl -X POST "https://function-auto-startup.azurewebsites.net/api/start-vms?code=<master-key>"
```

**브라우저에서:**
```
https://function-auto-startup.azurewebsites.net/api/start-vms?code=<function-key>
```

**Azure Portal에서:**
1. Function App → Functions → `StartVMsManual` 선택
2. "Code + Test" 탭
3. "Test/Run" 버튼 클릭

### 방법 2: Azure Portal에서 Timer Function 수동 실행

1. Azure Portal → Function App → Functions
2. `start_vm_timer_function` 선택
3. "Code + Test" 탭
4. "Test/Run" 버튼 클릭
5. 입력 필드에 빈 JSON `{}` 입력 후 실행

### 방법 3: 로컬에서 테스트

#### 전제 조건
- Azure Functions Core Tools 설치
- Azure CLI 로그인 (`az login`)
- `local.settings.json` 파일 설정

#### 실행 방법

```bash
# 가상 환경 활성화
source .venv/bin/activate  # Windows: .venv\Scripts\activate

# 로컬 실행
func start

# 별도 터미널에서 HTTP 요청
curl http://localhost:7071/api/start-vms
```

또는 Python에서 직접 테스트:

```python
# test_local.py
import sys
sys.path.insert(0, '.')

from start_vm import start_vm_timer

class MockTimer:
    past_due = False

mock_timer = MockTimer()
start_vm_timer.main(mock_timer)
```

### 방법 4: Timer 스케줄 임시 변경 (빠른 테스트)

테스트를 위해 Timer를 짧은 간격으로 변경할 수 있습니다:

```python
# function_app.py에서 임시로 변경
@app.timer_trigger(schedule="0 */5 * * * *", ...)  # 5분마다 실행
# 또는
@app.timer_trigger(schedule="0 * * * * *", ...)   # 매 시간마다 실행
```

**주의:** 테스트 후 원래 시간(`0 0 20 * * *`)으로 되돌려야 합니다.

## 테스트 체크리스트

### 사전 확인
- [ ] Function App이 배포되어 실행 중인지 확인
- [ ] 환경 변수(`AZURE_SUBSCRIPTION_ID`, `AZURE_VM_LIST`)가 올바르게 설정되었는지 확인
- [ ] Managed Identity 권한이 각 VM에 부여되었는지 확인

### 실행 확인
- [ ] HTTP 요청이 성공적으로 완료되는지 확인
- [ ] 로그에서 각 VM의 상태가 올바르게 확인되는지 확인
- [ ] VM이 실제로 시작되는지 확인 (Azure Portal에서 확인)

### 로그 확인

```bash
# 실시간 로그 스트리밍
az functionapp log tail \
  --name function-auto-startup \
  --resource-group rg-common-gitlabrunner-kc-01

# Application Insights 로그 확인 (Azure Portal)
# Function App → Monitor → Log stream
```

## 예상 로그 출력

정상 실행 시 다음과 같은 로그가 출력됩니다:

```
VM 자동 시작 함수가 실행되었습니다. (Timer: False)
처리할 VM 개수: 3
  - vm-gitlab-kc-01 (rg-common-gitlab-cjs-kc-01)
  - vm-gitlabrunner-kc-01 (rg-common-gitlabrunner-kc-01)
  - vm-nexus-kc-02 (rg-common-nexus-cjs-kc-01)
Azure 인증 중...
============================================================
VM 처리 시작: vm-gitlab-kc-01
============================================================
[vm-gitlab-kc-01] VM 상태 확인 중... (리소스 그룹: rg-common-gitlab-cjs-kc-01)
[vm-gitlab-kc-01] 현재 상태: deallocated
[vm-gitlab-kc-01] VM 시작 중...
[vm-gitlab-kc-01] VM 시작 완료
[vm-gitlab-kc-01] 시작 작업이 성공적으로 완료되었습니다.
...
============================================================
처리 완료: 성공 3개, 실패 0개 (총 3개)
============================================================
```

## 문제 해결

### HTTP 401 Unauthorized
- Function Key가 올바른지 확인
- URL에 `code` 파라미터가 포함되어 있는지 확인

### HTTP 500 Internal Server Error
- 로그를 확인하여 구체적인 오류 메시지 확인
- 환경 변수 설정 확인
- Managed Identity 권한 확인

### VM이 시작되지 않음
- VM 상태 확인 (이미 실행 중일 수 있음)
- Managed Identity 권한 확인
- 리소스 그룹 및 VM 이름이 정확한지 확인

## 빠른 테스트 스크립트

```bash
#!/bin/bash
# quick-test.sh

FUNCTION_APP_NAME="function-auto-startup"
RESOURCE_GROUP="rg-common-gitlabrunner-kc-01"

# Function Key 가져오기
FUNCTION_KEY=$(az functionapp function keys list \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --function-name StartVMsManual \
  --query "default" -o tsv)

# 실행
echo "VM 시작 함수 실행 중..."
curl -X POST "https://${FUNCTION_APP_NAME}.azurewebsites.net/api/start-vms?code=${FUNCTION_KEY}"

echo -e "\n\n로그 확인:"
az functionapp log tail --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP
```
