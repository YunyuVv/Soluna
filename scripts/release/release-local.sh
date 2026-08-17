#!/bin/zsh
#
# release-local.sh — 在本地 Mac 上构建「未签名 DMG」并自动升版本号
# （开源技术人分发路线；与 CI 工作流 .github/workflows/build-dmg.yml 同口径）
#
# 版本号来源（升级就是改这两个字段，写在 Soluna.xcodeproj/project.pbxproj）：
#   MARKETING_VERSION        —— 对外版本号，如 1.0.0，对应 git tag v1.0.0
#   CURRENT_PROJECT_VERSION  —— 内部构建号，每发版 +1（整数）
# git tag 约定：v<MARKETING_VERSION>（如 v1.0.0）；CI 工作流仅在该 tag 推送时自动出 Release。
#
# 用法：
#   ./scripts/release-local.sh                # 默认 patch +1（1.0.0 -> 1.0.1），构建未签名 DMG
#   ./scripts/release-local.sh minor          # 升 minor（1.0.0 -> 1.1.0）
#   ./scripts/release-local.sh major          # 升 major（1.0.0 -> 2.0.0）
#   ./scripts/release-local.sh 1.3.0          # 指定具体版本号
#   ./scripts/release-local.sh --no-bump      # 不升版本号，直接按当前版本构建
#   ./scripts/release-local.sh patch --tag    # 升版本 + 打本地 git tag vX.Y.Z（不推送，避免触发 CI 重复发布）
#
set -euo pipefail

# 切到仓库根目录（脚本位于 scripts/release/，故回退两级到仓库根）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../.."

PBXPROJ="Soluna.xcodeproj/project.pbxproj"

# ── 0. 前置检查 ──────────────────────────────────────────────
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "✗ 未找到 xcodebuild（请安装 Xcode 命令行工具）" >&2; exit 1
fi

# ── 1. 解析参数 ──────────────────────────────────────────────
BUMP="patch"          # major | minor | patch | <x.y.z>
DO_BUMP=1
DO_TAG=0
for a in "$@"; do
  case "$a" in
    --no-bump) DO_BUMP=0 ;;
    --tag)     DO_TAG=1 ;;
    major|minor|patch) BUMP="$a" ;;
    *)                 BUMP="$a" ;;   # 形如 1.3.0
  esac
done

# ── 2. 读取当前版本（从 pbxproj 解析 MARKETING_VERSION / CURRENT_PROJECT_VERSION）──
CUR_VER=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed -E 's/.*= *([0-9]+\.[0-9]+\.[0-9]+);.*/\1/')
CUR_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | sed -E 's/.*= *([0-9]+);.*/\1/')
CUR_VER="${CUR_VER:-0.0.0}"
CUR_BUILD="${CUR_BUILD:-0}"

# ── 3. 计算新版本号 ──────────────────────────────────────────
if [ "$DO_BUMP" -eq 0 ]; then
  NEW_VER="$CUR_VER"
  NEW_BUILD=$((CUR_BUILD + 1))
else
  if [[ "$BUMP" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    NEW_VER="$BUMP"
    NEW_BUILD=$((CUR_BUILD + 1))
  else
    IFS='.' read -r MAJ MIN PAT <<< "$CUR_VER"
    MAJ=${MAJ:-0}; MIN=${MIN:-0}; PAT=${PAT:-0}
    case "$BUMP" in
      major) MAJ=$((MAJ+1)); MIN=0; PAT=0 ;;
      minor) MIN=$((MIN+1)); PAT=0 ;;
      patch) PAT=$((PAT+1)) ;;
    esac
    NEW_VER="$MAJ.$MIN.$PAT"
    NEW_BUILD=$((CUR_BUILD + 1))
  fi
fi

echo "版本：$CUR_VER (build $CUR_BUILD)  →  $NEW_VER (build $NEW_BUILD)"

# ── 4. 写回 pbxproj（版本升级核心步骤，Debug/Release 两处一并更新）──
sed -i '' -E "s/(MARKETING_VERSION = )[0-9]+\.[0-9]+\.[0-9]+;/\1${NEW_VER};/" "$PBXPROJ"
sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )[0-9]+;/\1${NEW_BUILD};/" "$PBXPROJ"

# ── 5. 未签名 Release 构建 ───────────────────────────────────
echo "▶ 构建未签名 Release app…"
APP_PATH="$PWD/build/Release/Soluna.app"
rm -rf "$APP_PATH"
xcodebuild -project Soluna.xcodeproj \
  -scheme Soluna \
  -configuration Release \
  build \
  ARCHS="arm64" \
  CONFIGURATION_BUILD_DIR="$PWD/build/Release" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  ENABLE_HARDENED_RUNTIME=NO

# ── 6. 打包 DMG（create-dmg，图标精确定位：App 左、Applications 右）──
echo "▶ 检查 create-dmg…"
if ! command -v create-dmg >/dev/null 2>&1; then
  echo "  未找到 create-dmg，安装中：brew install create-dmg"
  brew install create-dmg
fi

echo "▶ 打包 DMG (create-dmg)…"
DMG_PATH="$PWD/build/Soluna-${NEW_VER}.dmg"
create-dmg \
  --volname "Soluna" \
  --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
  --app-drop-link 600 180 \
  --skip-jenkins \
  --no-internet-enable \
  --hide-extension "Soluna" \
  "$DMG_PATH" \
  "$APP_PATH"
echo "  产物大小：$(du -h "$DMG_PATH" | cut -f1)"

# ── 7. 可选：打本地 git tag（不推送，避免触发 CI 重复发版）───
if [ "$DO_TAG" -eq 1 ]; then
  TAG="v${NEW_VER}"
  if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "⚠ tag $TAG 已存在，跳过打 tag" >&2
  else
    git add "$PBXPROJ"
    git commit -m "chore: 升版本至 $NEW_VER (build $NEW_BUILD)"
    git tag "$TAG"
    echo "▶ 已打本地 tag $TAG（未推送）。需要发 GitHub Release 时执行：git push origin $TAG"
  fi
fi

echo ""
echo "✅ 完成！未签名 DMG 路径："
echo "   $DMG_PATH"
echo ""
echo "用户侧安装（未签名包）："
echo "   sudo xattr -r -d com.apple.quarantine /Applications/Soluna.app"
echo "   右键 Soluna.app → 打开 → 「仍要打开」"
