#!/bin/bash

# Azure Function ZIP 배포 스크립트
# 사용법:
#   CI (의존성 포함 ZIP): ./deploy.sh <function-app-name> <resource-group-name> deploy.zip
#   로컬 (소스만 ZIP):    ./deploy.sh <function-app-name> <resource-group-name>

set -e

FUNCTION_APP_NAME=$1
RESOURCE_GROUP=$2
PREBUILT_ZIP=$3

if [ -z "$FUNCTION_APP_NAME" ] || [ -z "$RESOURCE_GROUP" ]; then
    echo "사용법: ./deploy.sh <function-app-name> <resource-group-name> [deploy.zip]"
    exit 1
fi

if [ -n "$PREBUILT_ZIP" ] && [ -f "$PREBUILT_ZIP" ]; then
    if command -v realpath >/dev/null 2>&1; then
        DEPLOY_PACKAGE=$(realpath "$PREBUILT_ZIP")
    else
        DEPLOY_PACKAGE=$(cd "$(dirname "$PREBUILT_ZIP")" && pwd)/$(basename "$PREBUILT_ZIP")
    fi
    echo "사전 빌드 패키지 사용: $DEPLOY_PACKAGE (의존성 포함, 원격 빌드 비활성화)"
    BUILD_REMOTE="false"
    echo "배포 전 앱 설정: SCM_DO_BUILD_DURING_DEPLOYMENT=false, WEBSITE_RUN_FROM_PACKAGE 제거(wwwroot에 압축 해제)"
    az functionapp config appsettings set --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" \
      --settings SCM_DO_BUILD_DURING_DEPLOYMENT=false --output none 2>/dev/null || true
    az functionapp config appsettings delete --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" \
      --setting-names WEBSITE_RUN_FROM_PACKAGE --output none 2>/dev/null || true
else
    echo "배포 패키지 준비 중 (소스만, 원격 빌드 활성화)..."
    TEMP_DIR=$(mktemp -d)
    DEPLOY_PACKAGE="$TEMP_DIR/function-app.zip"
    mkdir -p "$TEMP_DIR/start_vm"
    cp function_app.py "$TEMP_DIR/"
    cp host.json "$TEMP_DIR/"
    cp requirements.txt "$TEMP_DIR/"
    cp start_vm/__init__.py "$TEMP_DIR/start_vm/"
    cd "$TEMP_DIR"
    python3 -c "
import zipfile
import os
with zipfile.ZipFile('$DEPLOY_PACKAGE', 'w', zipfile.ZIP_DEFLATED) as zipf:
    for root, dirs, files in os.walk('.'):
        for file in files:
            file_path = os.path.join(root, file)
            arcname = os.path.relpath(file_path, '.')
            zipf.write(file_path, arcname)
" 2>/dev/null || (zip -r "$DEPLOY_PACKAGE" . > /dev/null && true)
    cd - > /dev/null
    BUILD_REMOTE="true"
fi

echo "Azure Function App에 배포 중: $FUNCTION_APP_NAME"

if [ "$BUILD_REMOTE" = "true" ]; then
  az functionapp deployment source config-zip \
    --resource-group "$RESOURCE_GROUP" \
    --name "$FUNCTION_APP_NAME" \
    --src "$DEPLOY_PACKAGE" \
    --build-remote true
else
  az functionapp deployment source config-zip \
    --resource-group "$RESOURCE_GROUP" \
    --name "$FUNCTION_APP_NAME" \
    --src "$DEPLOY_PACKAGE"
fi

[ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
echo "배포 완료!"
