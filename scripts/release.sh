#!/bin/bash
# NovaLaunch Release Build Script
# 用法: ./scripts/release.sh <版本号>
# 示例: ./scripts/release.sh 1.0.1
#
# 步骤:
# 1. 更新 Info.plist 版本号
# 2. Xcode 归档构建
# 3. 创建 .zip 归档
# 4. 生成 appcast.json 更新条目
# 5. 输出发布说明

set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "用法: $0 <版本号>  例如: $0 1.0.1"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="/tmp/NovaLaunch-Release-$VERSION"
ARCHIVE_PATH="$BUILD_DIR/NovaLaunch-$VERSION"

echo "🚀 开始构建 NovaLaunch v$VERSION"

# Step 1: 更新版本号
echo "📝 更新版本号..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
    "$PROJECT_DIR/NovaLaunch/Info.plist"

# Step 2: 构建 Release 版本
echo "🔨 编译 Release 版本..."
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
    -scheme NovaLaunch \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/build" \
    -quiet 2>&1 | tail -5

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ 构建失败"
    exit 1
fi

# Step 3: 找到并复制 .app
echo "📦 打包..."
APP_PATH="$BUILD_DIR/build/Build/Products/Release/NovaLaunch.app"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ 未找到构建产物: $APP_PATH"
    exit 1
fi

mkdir -p "$ARCHIVE_PATH"
cp -R "$APP_PATH" "$ARCHIVE_PATH/"
xattr -dr com.apple.quarantine "$ARCHIVE_PATH/NovaLaunch.app"

# Step 4: 创建 .zip
cd "$ARCHIVE_PATH"
zip -r -q "NovaLaunch-v$VERSION.zip" "NovaLaunch.app"
ZIP_SIZE=$(du -sh "NovaLaunch-v$VERSION.zip" | cut -f1)

# Step 5: 更新 appcast.json
echo "📋 更新 appcast.json..."
cat > "$PROJECT_DIR/appcast.json" << EOF
{
  "version": "$VERSION",
  "downloadURL": "https://github.com/YOUR_USER/NovaLaunch/releases/download/v$VERSION/NovaLaunch-v$VERSION.zip",
  "notes": "NovaLaunch $VERSION\n\n包含性能优化和问题修复。",
  "minVersion": "14.0",
  "isCritical": false
}
EOF

echo ""
echo "✅ NovaLaunch v$VERSION 构建完成！"
echo ""
echo "📍 产物位置:"
echo "   .app:  $ARCHIVE_PATH/NovaLaunch.app"
echo "   .zip:  $ARCHIVE_PATH/NovaLaunch-v$VERSION.zip ($ZIP_SIZE)"
echo ""
echo "📋 发布步骤:"
echo "   1. 将 NovaLaunch-v$VERSION.zip 上传到 GitHub Releases"
echo "   2. 将 appcast.json 上传到你的网站/GitHub Pages"
echo "   3. 更新 UpdateService.swift 中的 appcastURL 为实际地址"
echo ""
