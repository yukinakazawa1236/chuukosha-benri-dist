#!/bin/bash
# ESCO Drive（Mac・見る専用）のインストール／更新
#   A) 共有フォルダの中の install-mac.sh を実行する（おすすめ）：
#        bash "（共有フォルダ）/install-mac.sh"
#      → インストールと同時に、この共有フォルダが、共有フォルダとして設定されます。
#   B) インターネットから：
#        curl -fsSL https://raw.githubusercontent.com/yukinakazawa1236/chuukosha-benri-dist/main/install-mac.sh | bash
#      → 共有フォルダは、あとで、画面の「設定」→「データの共有」で選びます。
# 管理者権限は不要です。入る場所：~/Applications/ESCODrive（本体）と ~/Applications/ESCO Drive.app（起動用）
# データは ~/Library/Application Support/udgarage-auction にできます（再実行しても消えません）。
# このPC（Mac）は、USSの取得はできません（USBキーがMacに対応していないため）。共有フォルダから、データを取り込んで見ます。

set -euo pipefail

BASE="${ESCO_BASE_URL:-https://raw.githubusercontent.com/yukinakazawa1236/chuukosha-benri-dist/main}"
NODE_VERSION="${ESCO_NODE_VERSION:-v24.21.0}"
HOME_DIR="${ESCO_HOME:-$HOME/Applications}"
DATA_DIR="${ESCO_DATA_DIR:-$HOME/Library/Application Support/udgarage-auction}"
APP_DIR="$HOME_DIR/ESCODrive"
# 起動用のアプリ（ESCO Drive.app）は、Macの「アプリケーション」フォルダに置く（書き込めないときだけ、ホームの Applications）
APPS_DIR="${HOME_DIR}"
if [ -z "${ESCO_TEST:-}" ] && [ -z "${ESCO_HOME:-}" ] && [ -d "/Applications" ] && [ -w "/Applications" ]; then APPS_DIR="/Applications"; fi
APP_BUNDLE="${APPS_DIR}/ESCO Drive.app"
PING_URL="http://127.0.0.1:3847/api/ping"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say() { printf '\n== %s\n' "$1"; }
fail() { printf '\n[エラー] %s\n' "$1" >&2; exit 1; }
sha256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1; else sha256sum "$1" | cut -d' ' -f1; fi; }
is_up() { curl -fs --max-time 2 "$PING_URL" >/dev/null 2>&1; }
wait_up() { local n="$1" i; for i in $(seq 1 "$n"); do is_up && return 0; sleep 1; done; return 1; }

[ "$(uname -s)" = "Darwin" ] || [ -n "${ESCO_TEST:-}" ] || fail "このスクリプトは、Mac用です。"

case "$(uname -m)" in
  arm64) NODE_ARCH="arm64" ;;
  x86_64) NODE_ARCH="x64" ;;
  *) fail "このMacのCPU（$(uname -m)）には、対応していません。" ;;
esac

# この install-mac.sh が、共有フォルダの中にあれば、そのフォルダを、共有フォルダとして設定する
SHARED_DIR="${ESCO_SHARED_DIR:-}"
if [ -z "$SHARED_DIR" ]; then
  SELF="${BASH_SOURCE[0]:-}"
  if [ -n "$SELF" ] && [ -f "$SELF" ]; then
    SELF_DIR="$(cd "$(dirname "$SELF")" 2>/dev/null && pwd || true)"
    if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/ESCO_Drive_shared.json" ]; then SHARED_DIR="$SELF_DIR"; fi
  fi
fi
[ -z "$SHARED_DIR" ] || echo "共有フォルダ：${SHARED_DIR}（インストール後、自動で設定します）"

mkdir -p "$HOME_DIR" "$APP_DIR"

# 失敗したときの手がかり（空き容量・書き込み権限）
diagnose() {
  printf '\n--- 手がかり ---\n' >&2
  printf '使用者: %s\n' "$(whoami)" >&2
  df -h "$HOME_DIR" 2>&1 | tail -2 >&2 || true
  ls -ld "$HOME_DIR" "$APP_DIR" 2>&1 >&2 || true
  printf 'ヒント：エージェント（Codexなど）から実行している場合は、「ネットワークと書き込みの許可（サンドボックスの外での実行）」を求めて、もう一度実行してください。\n' >&2
}

# 書き込めるかを、先に確かめる（書けないのに、途中まで進めない）
if ! ( : > "$APP_DIR/.write_test" ) 2>/dev/null; then diagnose; fail "インストール先（${APP_DIR}）に、書き込めません。"; fi
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

say "1/5 最新版を確認しています"
curl -fsSL "$BASE/latest.json?t=$(date +%s)" -o "$WORK/latest.json" || { diagnose; fail "最新版の情報を取得できません。ネットにつながっているか（エージェントの場合は、ネットワークの許可があるか）確認してください。"; }
VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$WORK/latest.json" | head -1)"
WANT_SHA="$(sed -n 's/.*"sha256": *"\([0-9a-f]*\)".*/\1/p' "$WORK/latest.json" | head -1)"
[ -n "$VERSION" ] && [ -n "$WANT_SHA" ] || fail "最新版の情報が、正しくありません。"
echo "バージョン $VERSION"

say "2/5 本体をダウンロードして、展開しています"
curl -fL --progress-bar "$BASE/app.zip?t=$(date +%s)" -o "$WORK/app.zip" || { diagnose; fail "本体をダウンロードできません。"; }
[ "$(sha256 "$WORK/app.zip")" = "$WANT_SHA" ] || fail "ダウンロードしたファイルが壊れています（確認の値が一致しません）。もう一度実行してください。"
if ! extract_zip "$WORK/app.zip" "$APP_DIR"; then diagnose; fail "本体を展開できませんでした（ditto・unzip・tar のすべてで失敗）。表示された理由は、容量不足とは限りません（書き込みの許可なども、確認してください）。"; fi
for needed in server.mjs lib/launcher.mjs lib/shared.mjs public/index.html node_modules/xlsx/package.json; do
  [ -f "${APP_DIR}/${needed}" ] || { diagnose; fail "本体の展開が、不完全です（${needed} が見つかりません）。展開の途中で止まった可能性があります。もう一度実行してください。"; }
done

say "3/5 Node.js（実行に必要な部品）を入れています"
if [ ! -x "$APP_DIR/runtime/node" ]; then
  TARBALL="node-$NODE_VERSION-darwin-$NODE_ARCH.tar.gz"
  curl -fL --progress-bar "https://nodejs.org/dist/$NODE_VERSION/$TARBALL" -o "$WORK/$TARBALL" || { diagnose; fail "Node.jsをダウンロードできません。"; }
  curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/SHASUMS256.txt" -o "$WORK/SHASUMS256.txt" || fail "Node.jsの確認用の情報を取得できません。"
  NODE_WANT="$(grep " $TARBALL\$" "$WORK/SHASUMS256.txt" | cut -d' ' -f1)"
  [ -n "$NODE_WANT" ] && [ "$(sha256 "$WORK/$TARBALL")" = "$NODE_WANT" ] || fail "Node.jsのファイルが壊れています（確認の値が一致しません）。"
  mkdir -p "$WORK/node" "$APP_DIR/runtime"
  tar -xzf "$WORK/$TARBALL" -C "$WORK/node"
  cp "$WORK/node/node-$NODE_VERSION-darwin-$NODE_ARCH/bin/node" "$APP_DIR/runtime/node"
fi
chmod +x "$APP_DIR/runtime/node"
"$APP_DIR/runtime/node" -v >/dev/null 2>&1 || [ -n "${ESCO_TEST:-}" ] || fail "Node.jsを起動できません。"

# 共有フォルダの設定（アプリの初回起動のときに、読み込まれる）
if [ -n "$SHARED_DIR" ]; then
  mkdir -p "$DATA_DIR"
  NODE_BIN="$APP_DIR/runtime/node"; [ -z "${ESCO_TEST:-}" ] || NODE_BIN="node"
  SHARED_DIR="$SHARED_DIR" PRESET="$DATA_DIR/preset.json" "$NODE_BIN" -e 'require("fs").writeFileSync(process.env.PRESET, JSON.stringify({ sharedDir: process.env.SHARED_DIR }))' || fail "共有フォルダの設定を、書き込めませんでした。"
  echo "共有フォルダを、設定しました：$SHARED_DIR"
fi

say "4/5 起動用のアプリ（ESCO Drive.app）を作っています"
make_script_bundle() {
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
}
rm -rf "$APP_BUNDLE"
APP_KIND="osacompile"
# Mac標準の方式（AppleScriptのアプリ）：Mac標準の仕組みで作られるので、確実に開ける
if command -v osacompile >/dev/null 2>&1 && osacompile -o "$APP_BUNDLE" -e "do shell script \"cd '$APP_DIR' && ./runtime/node lib/launcher.mjs >/dev/null 2>&1 &\"" 2>"$WORK/osa.err"; then
  if [ -f "$APP_DIR/public/icon.icns" ]; then cp "$APP_DIR/public/icon.icns" "$APP_BUNDLE/Contents/Resources/applet.icns"; fi
else
  [ ! -s "$WORK/osa.err" ] || printf '（osacompile での作成に失敗：%s）\n' "$(head -c 200 "$WORK/osa.err")" >&2
  rm -rf "$APP_BUNDLE"
  APP_KIND="script"
  make_script_bundle
fi
# 簡易の署名（Macが、アプリを正しく扱えるように）と、「隔離」の印の除去
command -v codesign >/dev/null 2>&1 && codesign --force --deep -s - "$APP_BUNDLE" >/dev/null 2>&1 || true
xattr -dr com.apple.quarantine "$APP_BUNDLE" "$APP_DIR" 2>/dev/null || true
echo "起動用のアプリを作りました（方式：${APP_KIND}）"

# 前の版が置いた、別の場所のアプリ（ホームの Applications・デスクトップ）は、二重にならないように片づける
if [ -z "${ESCO_TEST:-}" ] && [ -z "${ESCO_HOME:-}" ]; then
  for OLD_APP in "${HOME}/Applications/ESCO Drive.app" "${HOME}/Desktop/ESCO Drive.app"; do
    if [ "${OLD_APP}" != "${APP_BUNDLE}" ] && [ -d "${OLD_APP}" ]; then rm -rf "${OLD_APP}" && echo "前の場所のアプリを、片づけました：${OLD_APP}"; fi
  done
fi

say "5/5 起動を確認しています"
if [ -n "${ESCO_NO_OPEN:-}" ] || [ -n "${ESCO_TEST:-}" ]; then
  echo "（起動の確認は、省きます）"
else
  # すでに、古い版が動いていれば、いったん終了して、新しい版で起動し直す
  if is_up; then curl -fs -X POST -H "X-UD-Ext: 1" "http://127.0.0.1:3847/api/quit" >/dev/null 2>&1 || true; sleep 3; fi
  open "$APP_BUNDLE" >/dev/null 2>"$WORK/open.err" || printf '（open で、開けませんでした：%s）\n' "$(head -c 200 "$WORK/open.err")" >&2
  if ! wait_up 25; then
    echo "アプリからの起動が、確認できなかったので、直接の方法で起動します"
    ( cd "$APP_DIR" && nohup ./runtime/node lib/launcher.mjs >/dev/null 2>&1 & )
    if ! wait_up 25; then
      printf '\n--- server.log（末尾）---\n' >&2
      tail -15 "$DATA_DIR/server.log" 2>/dev/null >&2 || echo "（まだ、記録がありません）" >&2
      fail "ESCO Drive を起動できませんでした。上の記録を、確認してください。"
    fi
  fi
  echo "起動しました。"
  if [ -n "$SHARED_DIR" ]; then
    sleep 4
    printf '共有フォルダの状態：'
    curl -fs --max-time 5 "http://127.0.0.1:3847/api/shared/status" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p' || true
  fi
fi

printf '\n完了しました（バージョン %s）。\n' "$VERSION"
printf '次回から、「アプリケーション」の「ESCO Drive」を、ダブルクリック（または、Spotlight で「ESCO Drive」）で、開けます。\n本体の場所：%s\n' "$APP_BUNDLE"
if [ -n "$SHARED_DIR" ]; then
  printf 'このMacは、見る専用です。共有フォルダ（%s）の最新データが、自動で取り込まれます。\n' "$SHARED_DIR"
else
  printf 'このMacは、見る専用です。画面の「設定」→「データの共有」で、共有フォルダを選んでください。\n'
fi
