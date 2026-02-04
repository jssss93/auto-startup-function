#!/bin/bash

# GitLab CI/CD 변수 설정을 위한 스크립트
# 사용법: ./setup-gitlab-variables.sh

set -e

echo "=========================================="
echo "GitLab CI/CD 변수 설정 가이드"
echo "=========================================="
echo ""

# Azure Service Principal 생성
echo "1. Azure Service Principal 생성 중..."
echo "----------------------------------------"

read -p "Service Principal 이름 (기본: gitlab-ci-function-deploy): " SP_NAME
SP_NAME=${SP_NAME:-gitlab-ci-function-deploy}

read -p "구독 ID: " SUBSCRIPTION_ID
read -p "리소스 그룹 이름: " RESOURCE_GROUP

echo ""
echo "Service Principal 생성 중..."
SP_OUTPUT=$(az ad sp create-for-rbac \
  --name "$SP_NAME" \
  --role contributor \
  --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
  --output json)

APP_ID=$(echo $SP_OUTPUT | jq -r '.appId')
PASSWORD=$(echo $SP_OUTPUT | jq -r '.password')
TENANT=$(echo $SP_OUTPUT | jq -r '.tenant')

echo ""
echo "✓ Service Principal 생성 완료!"
echo ""
echo "=========================================="
echo "생성된 정보:"
echo "=========================================="
echo "AZURE_CLIENT_ID:     $APP_ID"
echo "AZURE_CLIENT_SECRET: $PASSWORD"
echo "AZURE_TENANT_ID:     $TENANT"
echo "AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
echo ""
echo "=========================================="
echo "GitLab에 변수 설정 방법:"
echo "=========================================="
echo ""
echo "1. GitLab 프로젝트로 이동"
echo "2. Settings → CI/CD → Variables"
echo "3. Add variable 클릭"
echo ""
echo "다음 변수들을 추가하세요:"
echo ""
echo "변수명: AZURE_CLIENT_ID"
echo "값: $APP_ID"
echo "옵션: Protected 체크 (프로덕션 브랜치에서만 사용)"
echo ""
echo "변수명: AZURE_CLIENT_SECRET"
echo "값: $PASSWORD"
echo "옵션: ✅ Masked 체크, ✅ Protected 체크"
echo ""
echo "변수명: AZURE_TENANT_ID"
echo "값: $TENANT"
echo "옵션: Protected 체크 (선택)"
echo ""
echo "변수명: AZURE_SUBSCRIPTION_ID"
echo "값: $SUBSCRIPTION_ID"
echo "옵션: Protected 체크 (선택)"
echo ""
echo "=========================================="
echo ""
echo "⚠️  중요: AZURE_CLIENT_SECRET 값을 복사해두세요!"
echo "          이 스크립트를 다시 실행하면 새로운 Secret이 생성됩니다."
echo ""
