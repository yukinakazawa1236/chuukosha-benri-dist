#!/bin/bash
# ESCO Drive（Mac・見る専用）のインストール／更新
#   Terminal に、次の1行を貼って実行する：
#   curl -fsSL https://raw.githubusercontent.com/yukinakazawa1236/chuukosha-benri-dist/main/install-mac.sh | bash
# 管理者権限は不要です。入る場所：~/Applications/ESCODrive（本体）と ~/Applications/ESCO Drive.app（起動用）
# データは ~/Library/Application Support/udgarage-auction にできます（再実行しても消えません）。
# このPC（Mac）は、USSの取得はできません（USBキーがMacに対応していないため）。共有フォルダから、データを取り込んで見ます。

set -euo pipefail

BASE="${ESCO_BASE_URL:-https://raw.githubusercontent.com/yukinakazawa1236/chuukosha-benri-dist/main}"
NODE_VERSION="${ESCO_NODE_VERSION:-v24.21.0}"
HOME_DIR="${ESCO_HOME:-$HOME/Applications}"
APP_DIR="$HOME_DIR/ESCODrive"
APP_BUNDLE="$HOME_DIR/ESCO Drive.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say() { printf '\n== %s\n' "$1"; }
fail() { printf '\n[エラー] %s\n' "$1" >&2; exit 1; }
sha256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1; else sha256sum "$1" | cut -d' ' -f1; fi; }

[ "$(uname -s)" = "Darwin" ] || [ -n "${ESCO_TEST:-}" ] || fail "このスクリプトは、Mac用です。"

case "$(uname -m)" in
  arm64) NODE_ARCH="arm64" ;;
  x86_64) NODE_ARCH="x64" ;;
  *) fail "このMacのCPU（$(uname -m)）には、対応していません。" ;;
esac

mkdir -p "$HOME_DIR" "$APP_DIR"

# 失敗したときの手がかり（空き容量・書き込み権限）
diagnose() {
  printf '\n--- 手がかり ---\n' >&2
  printf '使用者: %s\n' "$(whoami)" >&2
  df -h "$HOME_DIR" 2>&1 | tail -2 >&2 || true
  ls -ld "$HOME_DIR" "$APP_DIR" 2>&1 >&2 || true
  printf 'ヒント：エージェント（Codexなど）から実行している場合は、「書き込みの許可（サンドボックスの外での実行）」を求めて、もう一度実行してください。\n' >&2
}

# 書き込めるかを、先に確かめる（書けないのに、途中まで進めない）
if ! ( : > "$APP_DIR/.write_test" ) 2>/dev/null; then diagnose; fail "インストール先（$APP_DIR）に、書き込めません。"; fi
rm -f "$APP_DIR/.write_test"

# zipの展開：Mac標準の ditto（Windowsで作ったzipも、日本語の名前も扱える）→ unzip → tar の順に試す
extract_zip() {
  local zip="$1" dest="$2"
  if command -v ditto >/dev/null 2>&1; then
    if ditto -x -k "$zip" "$dest" 2>"$WORK/extract.err"; then return 0; fi
    printf '（ditto での展開に失敗：%s）\n' "$(head -c 300 "$WORK/extract.err")" >&2
    rm -rf "$dest"; mkdir -p "$dest"
  fi
  if command -v unzip >/dev/null 2>&1; then
    if unzip -q -o "$zip" -d "$dest" 2>"$WORK/extract.err"; then return 0; fi
    printf '（unzip での展開に失敗：%s）\n' "$(head -c 300 "$WORK/extract.err")" >&2
    rm -rf "$dest"; mkdir -p "$dest"
  fi
  if tar -xf "$zip" -C "$dest" 2>"$WORK/extract.err"; then return 0; fi
  printf '（tar での展開に失敗：%s）\n' "$(head -c 300 "$WORK/extract.err")" >&2
  return 1
}

say "1/4 最新版を確認しています"
curl -fsSL "$BASE/latest.json?t=$(date +%s)" -o "$WORK/latest.json" || fail "最新版の情報を取得できません。ネットにつながっているか確認してください。"
VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$WORK/latest.json" | head -1)"
WANT_SHA="$(sed -n 's/.*"sha256": *"\([0-9a-f]*\)".*/\1/p' "$WORK/latest.json" | head -1)"
[ -n "$VERSION" ] && [ -n "$WANT_SHA" ] || fail "最新版の情報が、正しくありません。"
echo "バージョン $VERSION"

say "2/4 本体をダウンロードしています"
curl -fL --progress-bar "$BASE/app.zip?t=$(date +%s)" -o "$WORK/app.zip" || fail "本体をダウンロードできません。"
[ "$(sha256 "$WORK/app.zip")" = "$WANT_SHA" ] || fail "ダウンロードしたファイルが壊れています（確認の値が一致しません）。もう一度実行してください。"
if ! extract_zip "$WORK/app.zip" "$APP_DIR"; then diagnose; fail "本体を展開できませんでした。"; fi
[ -f "$APP_DIR/server.mjs" ] || { diagnose; fail "本体を展開できませんでした（server.mjs が見つかりません）。"; }

say "3/4 Node.js（実行に必要な部品）を入れています"
if [ ! -x "$APP_DIR/runtime/node" ]; then
  TARBALL="node-$NODE_VERSION-darwin-$NODE_ARCH.tar.gz"
  curl -fL --progress-bar "https://nodejs.org/dist/$NODE_VERSION/$TARBALL" -o "$WORK/$TARBALL" || fail "Node.jsをダウンロードできません。"
  curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/SHASUMS256.txt" -o "$WORK/SHASUMS256.txt" || fail "Node.jsの確認用の情報を取得できません。"
  NODE_WANT="$(grep " $TARBALL\$" "$WORK/SHASUMS256.txt" | cut -d' ' -f1)"
  [ -n "$NODE_WANT" ] && [ "$(sha256 "$WORK/$TARBALL")" = "$NODE_WANT" ] || fail "Node.jsのファイルが壊れています（確認の値が一致しません）。"
  mkdir -p "$WORK/node" "$APP_DIR/runtime"
  tar -xzf "$WORK/$TARBALL" -C "$WORK/node"
  cp "$WORK/node/node-$NODE_VERSION-darwin-$NODE_ARCH/bin/node" "$APP_DIR/runtime/node"
fi
chmod +x "$APP_DIR/runtime/node"
"$APP_DIR/runtime/node" -v >/dev/null 2>&1 || [ -n "${ESCO_TEST:-}" ] || fail "Node.jsを起動できません。"

say "4/4 起動用のアプリ（ESCO Drive.app）を作っています"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cat > "$APP_BUNDLE/Contents/MacOS/ESCODrive" <<EOS
#!/bin/bash
ROOT="$APP_DIR"
cd "\$ROOT" || exit 1
exec "\$ROOT/runtime/node" lib/launcher.mjs
EOS
chmod +x "$APP_BUNDLE/Contents/MacOS/ESCODrive"
[ -f "$APP_DIR/public/icon.icns" ] && cp "$APP_DIR/public/icon.icns" "$APP_BUNDLE/Contents/Resources/icon.icns"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'EOP'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ESCO Drive</string>
  <key>CFBundleDisplayName</key><string>ESCO Drive</string>
  <key>CFBundleIdentifier</key><string>jp.esco.drive</string>
  <key>CFBundleExecutable</key><string>ESCODrive</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOP
# ダウンロードしたファイルに付く「隔離」の印を外す（curlで入れたものには、付かない）
xattr -dr com.apple.quarantine "$APP_BUNDLE" "$APP_DIR" 2>/dev/null || true

printf '\n完了しました（バージョン %s）。\n' "$VERSION"
printf '起動するには：「%s」をダブルクリック（または、Spotlight で「ESCO Drive」と入れる）。\n' "$APP_BUNDLE"
printf 'このMacは、見る専用です。USBキーのPCが取得した結果を、「設定」→「データの共有」で、共有フォルダから取り込んで見ます。\n'
[ -n "${ESCO_NO_OPEN:-}" ] || [ -n "${ESCO_TEST:-}" ] || open "$APP_BUNDLE" || true
