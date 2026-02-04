#!/bin/bash

# 빠른 테스트 스크립트
# 사용법: ./quick-test.sh

FUNCTION_APP_NAME="function-auto-startup"
RESOURCE_GROUP="rg-common-gitlabrunner-kc-01"

echo "=========================================="
echo "VM 자동 시작 함수 테스트"
echo "=========================================="
echo ""

# Function Key 가져오기
echo "Function Key 조회 중..."
FUNCTION_KEY=$(az functionapp function keys list \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --function-name StartVMsManual \
  --query "default" -o tsv 2>/dev/null)

if [ -z "$FUNCTION_KEY" ]; then
    echo "Function Key를 찾을 수 없습니다. Master Key를 사용합니다..."
    FUNCTION_KEY=$(az functionapp keys list \
      --name $FUNCTION_APP_NAME \
      --resource-group $RESOURCE_GROUP \
      --query "masterKey" -o tsv 2>/dev/null)
fi

if [ -z "$FUNCTION_KEY" ]; then
    echo "오류: Function Key를 가져올 수 없습니다."
    exit 1
fi

echo "✓ Function Key 조회 완료"
echo ""

# 실행
echo "VM 시작 함수 실행 중..."
echo "----------------------------------------"
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
  "https://${FUNCTION_APP_NAME}.azurewebsites.net/api/start-vms?code=${FUNCTION_KEY}")

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS/d')

echo ""
echo "응답 상태: $HTTP_STATUS"
echo "응답 내용:"
echo "$BODY"
echo ""

if [ "$HTTP_STATUS" = "200" ]; then
    echo "✓ 테스트 성공!"
else
    echo "✗ 테스트 실패 (HTTP $HTTP_STATUS)"
    echo ""
    echo "로그를 확인하세요:"
    echo "az functionapp log tail --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP"
fi

echo ""
echo "=========================================="
