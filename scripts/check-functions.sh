#!/bin/bash

# Azure Function App의 함수 목록과 상태를 자세히 확인하는 스크립트
# 사용법: ./check-functions.sh <function-app-name> <resource-group-name>

set -e

FUNCTION_APP_NAME=$1
RESOURCE_GROUP=$2

if [ -z "$FUNCTION_APP_NAME" ] || [ -z "$RESOURCE_GROUP" ]; then
    echo "사용법: ./check-functions.sh <function-app-name> <resource-group-name>"
    exit 1
fi

echo "=========================================="
echo "Function App 상태 확인"
echo "=========================================="
echo "Function App: $FUNCTION_APP_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo ""

# Function App 상태 확인
APP_STATE=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --query "state" -o tsv 2>/dev/null || echo "Unknown")
echo "Function App 상태: $APP_STATE"
echo ""

# 함수 목록 조회 (JSON)
FUNCTIONS_JSON=$(az functionapp function list --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --output json 2>/dev/null || echo "[]")

# 함수 개수 확인
FUNCTION_COUNT=$(echo "$FUNCTIONS_JSON" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data))" 2>/dev/null || echo "0")

echo "=========================================="
echo "등록된 함수 목록 ($FUNCTION_COUNT개)"
echo "=========================================="

if [ "$FUNCTION_COUNT" = "0" ]; then
    echo "⚠️  등록된 함수가 없습니다."
    echo ""
    echo "가능한 원인:"
    echo "  1. 배포 후 함수 인식까지 시간이 필요할 수 있습니다 (1-2분)"
    echo "  2. function_app.py가 올바르게 로드되지 않았을 수 있습니다"
    echo "  3. Python 패키지(azure-functions 등)가 설치되지 않았을 수 있습니다"
    echo ""
    echo "확인 방법:"
    echo "  - Azure Portal에서 Function App → Functions 메뉴 확인"
    echo "  - Log stream에서 Python 런타임 오류 확인"
    echo "  - 배포 로그 확인: https://${FUNCTION_APP_NAME}.scm.azurewebsites.net/api/deployments/latest/log"
else
    echo "$FUNCTIONS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for func in data:
    name = func.get('name', 'Unknown')
    state = func.get('config', {}).get('bindings', [{}])[0].get('type', 'Unknown')
    print(f'✅ {name}')
    print(f'   타입: {state}')
    print(f'   ID: {func.get(\"id\", \"N/A\")}')
    print('')
" 2>/dev/null || echo "$FUNCTIONS_JSON" | python3 -m json.tool 2>/dev/null || echo "$FUNCTIONS_JSON"
fi

echo ""
echo "=========================================="
echo "헬스체크 엔드포인트 테스트"
echo "=========================================="

HEALTH_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net/api/health"
echo "URL: $HEALTH_URL"
echo ""

# 헬스체크 호출
HTTP_CODE=$(curl -s -o /tmp/health_response.txt -w "%{http_code}" --max-time 10 "$HEALTH_URL" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ 헬스체크 성공 (HTTP $HTTP_CODE)"
    echo ""
    echo "응답 내용:"
    cat /tmp/health_response.txt | python3 -m json.tool 2>/dev/null || cat /tmp/health_response.txt
    echo ""
elif [ "$HTTP_CODE" = "404" ]; then
    echo "❌ 헬스체크 실패: 404 Not Found"
    echo "   → 함수가 등록되지 않았거나 라우팅이 설정되지 않았습니다"
    echo ""
elif [ "$HTTP_CODE" = "000" ]; then
    echo "⚠️  헬스체크 실패: 연결 불가 또는 타임아웃"
    echo "   → Function App이 아직 시작 중이거나 네트워크 문제일 수 있습니다"
    echo ""
else
    echo "⚠️  헬스체크 응답: HTTP $HTTP_CODE"
    echo ""
    echo "응답 내용:"
    cat /tmp/health_response.txt 2>/dev/null || echo "(응답 없음)"
    echo ""
fi

rm -f /tmp/health_response.txt

echo "=========================================="
echo "추가 확인 사항"
echo "=========================================="
echo "1. Azure Portal: https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FUNCTION_APP_NAME/functions"
echo "2. Log Stream: az functionapp log tail --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP"
echo "3. 배포 로그: https://${FUNCTION_APP_NAME}.scm.azurewebsites.net/api/deployments/latest/log"
echo ""
