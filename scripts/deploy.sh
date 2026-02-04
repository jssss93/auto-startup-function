#!/bin/bash

# Azure Function ZIP 배포 스크립트
# 사용법: ./deploy.sh <function-app-name> <resource-group-name>

set -e

FUNCTION_APP_NAME=$1
RESOURCE_GROUP=$2

if [ -z "$FUNCTION_APP_NAME" ] || [ -z "$RESOURCE_GROUP" ]; then
    echo "사용법: ./deploy.sh <function-app-name> <resource-group-name>"
    exit 1
fi

echo "배포 패키지 준비 중..."

# 임시 디렉토리 생성
TEMP_DIR=$(mktemp -d)
DEPLOY_PACKAGE="$TEMP_DIR/function-app.zip"

# 필요한 파일들만 복사
mkdir -p "$TEMP_DIR/start_vm"
cp function_app.py "$TEMP_DIR/"
cp host.json "$TEMP_DIR/"
cp requirements.txt "$TEMP_DIR/"
cp start_vm/__init__.py "$TEMP_DIR/start_vm/"

# ZIP 파일 생성 (Python zipfile 모듈 사용)
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
" || zip -r "$DEPLOY_PACKAGE" . > /dev/null
cd - > /dev/null

echo "Azure Function App에 배포 중: $FUNCTION_APP_NAME"

# ZIP 배포 (빌드 활성화)
az functionapp deployment source config-zip \
  --resource-group "$RESOURCE_GROUP" \
  --name "$FUNCTION_APP_NAME" \
  --src "$DEPLOY_PACKAGE" \
  --build-remote true

# 임시 디렉토리 정리
rm -rf "$TEMP_DIR"

echo "배포 완료!"
