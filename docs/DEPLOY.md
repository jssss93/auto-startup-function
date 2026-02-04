# 배포 가이드

이 문서는 Azure Function을 배포하는 다양한 방법을 설명합니다.

## 배포 방법 선택 가이드

| 방법 | 장점 | 단점 | 추천 상황 |
|------|------|------|----------|
| **Core Tools** | 간단하고 빠름 | 로컬 환경 필요 | 개발/테스트 |
| **ZIP 배포** | 소스 코드 직접 제어 | 수동 작업 필요 | 간단한 배포 |
| **GitHub Actions** | 자동화, CI/CD | 초기 설정 필요 | 프로덕션, 팀 협업 |
| **Azure Portal** | GUI 사용 | 수동 작업 | 비개발자 |

## 방법별 상세 가이드

### 1. Azure Functions Core Tools 배포

**전제 조건:**
- Azure Functions Core Tools 설치
- Azure CLI 로그인 (`az login`)

**배포 명령:**
```bash
func azure functionapp publish <function-app-name>
```

**장점:**
- 가장 간단한 방법
- 자동으로 의존성 설치 및 빌드
- 로컬 테스트와 동일한 환경

### 2. ZIP 배포 (소스 코드 업로드)

#### 방법 A: 제공된 스크립트 사용

```bash
./deploy.sh <function-app-name> <resource-group-name>
./deploy.sh function-auto-startup rg-common-gitlabrunner-kc-01
```

#### 방법 B: 수동 ZIP 배포

```bash
# 1. 배포 패키지 생성
zip -r function-app.zip . \
  -x "*.git*" \
  -x "*__pycache__*" \
  -x "*.venv*" \
  -x "*local.settings.json*" \
  -x "*.vscode*" \
  -x "*.idea*"

# 2. Azure CLI로 배포
az functionapp deployment source config-zip \
  --resource-group <resource-group-name> \
  --name <function-app-name> \
  --src function-app.zip
```

#### 방법 C: REST API를 통한 배포

```bash
# 1. Publish Profile 가져오기
az functionapp deployment list-publishing-profiles \
  --name <function-app-name> \
  --resource-group <resource-group-name> \
  --xml > publish-profile.xml

# 2. publishUrl, publishUsername, publishPassword 추출
# (XML 파일에서 확인)

# 3. ZIP 파일 업로드
curl -X POST \
  -u '<publishUsername>:<publishPassword>' \
  --data-binary @function-app.zip \
  https://<function-app-name>.scm.azurewebsites.net/api/zipdeploy?isAsync=true
```

**주의사항:**
- `requirements.txt`가 포함되어야 Azure에서 자동으로 패키지를 설치합니다
- `.funcignore`에 명시된 파일은 배포에서 제외됩니다

### 3. GitHub Actions CI/CD

#### 초기 설정

1. **GitHub Secrets 설정:**
   - `AZURE_FUNCTIONAPP_PUBLISH_PROFILE`: Function App의 Publish Profile
   - `AZURE_CREDENTIALS` (선택): Service Principal 정보 (JSON 형식)

2. **Publish Profile 가져오기:**
   ```bash
   az functionapp deployment list-publishing-profiles \
     --name <function-app-name> \
     --resource-group <resource-group-name> \
     --xml
   ```
   위 명령어의 출력을 복사하여 GitHub Secrets에 저장

3. **워크플로우 파일 수정:**
   `.github/workflows/deploy.yml`에서 `AZURE_FUNCTIONAPP_NAME` 설정

#### 배포 트리거

- `main` 브랜치에 push 시 자동 배포
- GitHub Actions 탭에서 수동 실행 가능 (`workflow_dispatch`)

#### 장점:
- 코드 변경 시 자동 배포
- 배포 이력 관리
- 팀 협업에 적합

### 4. Azure Portal 배포

1. Azure Portal에서 Function App 선택
2. 왼쪽 메뉴에서 **Deployment Center** 클릭
3. **Source** 선택:
   - **GitHub**: GitHub 저장소 연결
   - **Azure Repos**: Azure DevOps 연결
   - **Local Git**: 로컬 Git 저장소 설정
   - **External Git**: 외부 Git 저장소 연결
4. 저장소 정보 입력 및 연결
5. 배포 자동 시작

### 5. VS Code Extension 배포

1. VS Code에 **Azure Functions** 확장 설치
2. Azure 계정 로그인 (왼쪽 사이드바의 Azure 아이콘)
3. Function App 선택
4. 우클릭 → **Deploy to Function App** 선택
5. 배포 확인

## 배포 전 체크리스트

- [ ] `requirements.txt`에 모든 의존성 포함
- [ ] 환경 변수 설정 확인 (`AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `AZURE_VM_NAME`)
- [ ] Managed Identity 권한 확인
- [ ] `host.json` 설정 확인
- [ ] `.funcignore`에 불필요한 파일 제외 확인

## 배포 후 확인

```bash
# Function App 상태 확인
az functionapp show \
  --name <function-app-name> \
  --resource-group <resource-group-name>

# 함수 목록 확인
az functionapp function list \
  --name <function-app-name> \
  --resource-group <resource-group-name>

# 로그 확인
az functionapp log tail \
  --name <function-app-name> \
  --resource-group <resource-group-name>
```

## 문제 해결

### 배포 실패 시

1. **로그 확인:**
   ```bash
   az functionapp log tail --name <function-app-name> --resource-group <resource-group-name>
   ```

2. **배포 상태 확인:**
   Azure Portal → Function App → Deployment Center → Logs

3. **일반적인 문제:**
   - 의존성 설치 실패: `requirements.txt` 확인
   - 인증 오류: Managed Identity 또는 Publish Profile 확인
   - 타임아웃: 큰 파일이 포함되지 않았는지 확인

### 패키지 설치 문제

Azure Functions는 배포 시 `requirements.txt`를 자동으로 읽어 패키지를 설치합니다.
만약 패키지 설치가 실패하면:

1. Azure Portal → Function App → Configuration → General settings
2. **SCM_DO_BUILD_DURING_DEPLOYMENT** 설정을 `true`로 확인
3. 또는 배포 시 `--build remote` 옵션 사용 (Core Tools)

## 참고 자료

- [Azure Functions 배포 문서](https://docs.microsoft.com/azure/azure-functions/functions-deployment-technologies)
- [ZIP 배포 가이드](https://docs.microsoft.com/azure/azure-functions/deployment-zip-push)
- [GitHub Actions for Azure Functions](https://github.com/Azure/functions-action)
