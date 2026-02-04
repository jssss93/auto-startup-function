# GitLab CI/CD 설정 가이드

이 문서는 GitLab CI/CD를 사용하여 Azure Function을 자동 배포하는 방법을 설명합니다.

## 개요

`.gitlab-ci.yml` 파일이 프로젝트에 포함되어 있어, GitLab에 코드를 push하면 자동으로 빌드 및 배포가 실행됩니다.

## 파이프라인 구조

### Stages
1. **build**: 코드 검증 및 의존성 확인
2. **deploy**: Azure Function App에 배포

### Jobs

#### 1. `build`
- **트리거**: `main`, `develop` 브랜치 및 Merge Request
- **작업**: Python 코드 컴파일 검증 및 의존성 확인
- **아티팩트**: 빌드된 파일들을 다음 단계로 전달

#### 2. `deploy:development`
- **트리거**: `develop` 브랜치에 push 시 자동 실행
- **작업**: 개발 환경에 배포
- **환경**: development

#### 3. `deploy:production`
- **트리거**: `main` 브랜치에 push 시 **수동 승인 필요**
- **작업**: 프로덕션 환경에 배포
- **환경**: production
- **보안**: 수동 승인으로 실수로 인한 프로덕션 배포 방지

#### 4. `deploy:manual`
- **트리거**: 모든 브랜치에서 수동 실행 가능
- **작업**: 언제든지 수동으로 배포 가능
- **환경**: manual

## 필수 GitLab CI/CD 변수 설정

GitLab 프로젝트의 **Settings → CI/CD → Variables**에서 다음 변수들을 설정해야 합니다:

### 필수 변수

| 변수명 | 설명 | 예시 | 보호 여부 |
|--------|------|------|----------|
| `AZURE_CLIENT_ID` | Azure Service Principal Client ID | `12345678-1234-1234-1234-123456789abc` | ✅ |
| `AZURE_CLIENT_SECRET` | Azure Service Principal Client Secret | `your-secret-key` | ✅ |
| `AZURE_TENANT_ID` | Azure Tenant ID | `12345678-1234-1234-1234-123456789abc` | ✅ |
| `AZURE_SUBSCRIPTION_ID` | Azure 구독 ID | `12345678-1234-1234-1234-123456789abc` | ✅ |

### 선택적 변수 (기본값 사용 가능)

| 변수명 | 설명 | 기본값 |
|--------|------|--------|
| `FUNCTION_APP_NAME` | Function App 이름 | `function-auto-startup` |
| `RESOURCE_GROUP` | 리소스 그룹 이름 | `rg-common-gitlabrunner-kc-01` |

## Azure Service Principal 생성

GitLab CI/CD에서 Azure에 인증하기 위해 Service Principal이 필요합니다.

### 1. Service Principal 생성

```bash
# Service Principal 생성
az ad sp create-for-rbac \
  --name "gitlab-ci-function-deploy" \
  --role contributor \
  --scopes /subscriptions/<subscription-id>/resourceGroups/<resource-group-name>

# 출력 예시:
# {
#   "appId": "12345678-1234-1234-1234-123456789abc",
#   "displayName": "gitlab-ci-function-deploy",
#   "password": "your-secret-key",
#   "tenant": "12345678-1234-1234-1234-123456789abc"
# }
```

### 2. 필요한 권한 부여

Service Principal에 Function App 배포 권한이 필요합니다:

```bash
# Function App 리소스 그룹에 대한 Contributor 권한 (이미 위에서 부여됨)
# 추가로 필요한 권한이 있다면:
az role assignment create \
  --assignee <appId> \
  --role "Website Contributor" \
  --scope /subscriptions/<subscription-id>/resourceGroups/<resource-group-name>
```

### 3. GitLab 변수에 설정

생성된 Service Principal 정보를 GitLab CI/CD 변수에 설정:

1. GitLab 프로젝트 → **Settings → CI/CD → Variables**
2. **Add variable** 클릭
3. 각 변수 추가:
   - `AZURE_CLIENT_ID`: `appId` 값
   - `AZURE_CLIENT_SECRET`: `password` 값 (✅ **Masked** 체크)
   - `AZURE_TENANT_ID`: `tenant` 값
   - `AZURE_SUBSCRIPTION_ID`: 구독 ID

**보안 설정:**
- `AZURE_CLIENT_SECRET`은 반드시 **Masked** 및 **Protected** 체크
- 프로덕션 관련 변수는 **Protected** 체크 (프로덕션 브랜치에서만 사용)

## 사용 방법

### 자동 배포

1. **개발 환경 배포**:
   ```bash
   git checkout develop
   git add .
   git commit -m "Update function"
   git push origin develop
   ```
   → `develop` 브랜치에 push하면 자동으로 개발 환경에 배포됩니다.

2. **프로덕션 배포**:
   ```bash
   git checkout main
   git merge develop
   git push origin main
   ```
   → `main` 브랜치에 push하면 GitLab에서 수동 승인을 요청합니다.
   → GitLab → CI/CD → Pipelines에서 **Play** 버튼을 클릭하여 배포를 승인합니다.

### 수동 배포

언제든지 GitLab에서 수동으로 배포할 수 있습니다:

1. GitLab 프로젝트 → **CI/CD → Pipelines**
2. **Run pipeline** 클릭
3. 브랜치 선택
4. `deploy:manual` job의 **Play** 버튼 클릭

## 파이프라인 실행 확인

### GitLab에서 확인

1. **CI/CD → Pipelines**: 파이프라인 실행 상태 확인
2. 각 job 클릭하여 상세 로그 확인
3. **Environments**: 배포된 환경 확인

### Azure에서 확인

```bash
# Function App 상태 확인
az functionapp show \
  --name function-auto-startup \
  --resource-group rg-common-gitlabrunner-kc-01

# 함수 목록 확인
az functionapp function list \
  --name function-auto-startup \
  --resource-group rg-common-gitlabrunner-kc-01 \
  --output table

# 배포 이력 확인
az functionapp deployment list \
  --name function-auto-startup \
  --resource-group rg-common-gitlabrunner-kc-01 \
  --output table
```

## 문제 해결

### 인증 오류

**증상**: `az login` 실패

**해결 방법**:
- GitLab 변수에 Service Principal 정보가 올바르게 설정되었는지 확인
- Service Principal이 만료되지 않았는지 확인
- 권한이 올바르게 부여되었는지 확인

```bash
# Service Principal 테스트
az login --service-principal \
  -u "$AZURE_CLIENT_ID" \
  -p "$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID"
```

### 배포 실패

**증상**: ZIP 배포 실패

**해결 방법**:
- Function App 이름과 리소스 그룹이 올바른지 확인
- Service Principal에 배포 권한이 있는지 확인
- 로그에서 구체적인 오류 메시지 확인

### 빌드 실패

**증상**: Python 컴파일 오류

**해결 방법**:
- 로컬에서 코드가 정상적으로 실행되는지 확인
- `requirements.txt`에 모든 의존성이 포함되어 있는지 확인

## 고급 설정

### 특정 브랜치만 배포

`.gitlab-ci.yml`의 `only` 섹션을 수정:

```yaml
deploy:production:
  only:
    - main
    - tags  # 태그가 붙은 경우에도 배포
```

### 배포 전 테스트 추가

```yaml
test:
  stage: build
  script:
    - pip install pytest
    - pytest tests/
  only:
    - merge_requests
```

### 환경별 설정 분리

```yaml
variables:
  FUNCTION_APP_NAME_DEV: "function-auto-startup-dev"
  FUNCTION_APP_NAME_PROD: "function-auto-startup"
```

## 보안 모범 사례

1. ✅ **민감한 정보는 GitLab 변수로 관리**
2. ✅ **Service Principal Secret은 Masked 및 Protected 설정**
3. ✅ **프로덕션 배포는 수동 승인 필수**
4. ✅ **최소 권한 원칙**: Service Principal에 필요한 최소한의 권한만 부여
5. ✅ **정기적인 Secret 로테이션**

## 참고 자료

- [GitLab CI/CD 문서](https://docs.gitlab.com/ee/ci/)
- [Azure CLI 문서](https://docs.microsoft.com/cli/azure/)
- [Azure Functions 배포 가이드](https://docs.microsoft.com/azure/azure-functions/functions-deployment-technologies)
