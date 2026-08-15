#!/bin/zsh
# 安裝/更新 launchd 排程(2026-08-08)。
#
# 為什麼要有這支:plist 原本只存在於 ~/Library/LaunchAgents,未版控、
# 無文件——repo 搬家、路徑改變或換機都會讓排程靜默失效,而這個專案
# 已經有過「自動更新靜默斷 13 天」的前科。
#
# 用法:ops/launchd/install.sh   (從任何位置皆可)
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"

# --cli-only:只重編/替換 CLI binary,不碰 launchd。給 post-commit hook 用。
#
# 為什麼可以不 bootout/bootstrap:plist 的 ProgramArguments 指向**固定
# 路徑**,launchd 每次喚醒都重新 exec 那個檔案——換掉檔案,下一輪就是
# 新的。反過來說,在盤中對 intraday job 做 bootout/bootstrap 反而可能
# 打斷正在執行的那一輪。
CLI_ONLY=0
[ "${1:-}" = "--cli-only" ] && CLI_ONLY=1
# 🚨 必須解析到**原生執行檔**,不能用 PATH 上的 dart(2026-08-10 實機):
# `/opt/homebrew/bin/dart` → symlink → `.../flutter/bin/dart`(一支 **bash 腳本**)
# → `.../cache/dart-sdk/bin/dart`(真正的 Mach-O)。中間隔著腳本會讓
# macOS 的 TCC 責任鏈變成 launchd→zsh→bash→dart,請求者身分不穩定,於是
# 「想要取用其他 App 的資料」的授權對話框**每 5 分鐘重複跳一次**,盤中
# 洗版。直接指向原生檔,身分才固定、授權才記得住。
DART="$(command -v dart || echo /opt/homebrew/bin/dart)"
# 沿著 symlink 與 flutter 的 bash wrapper 解到底
_resolved="$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$DART" 2>/dev/null || echo "$DART")"
case "$(file -b "$_resolved" 2>/dev/null)" in
  *"shell script"*|*"Bourne"*)
    _sdk="$(dirname "$_resolved")/cache/dart-sdk/bin/dart"
    [ -x "$_sdk" ] && _resolved="$_sdk"
    ;;
esac
DART="$_resolved"
echo "dart 執行檔:$DART"

# ── 預先編譯 CLI ────────────────────────────────────────────────────────
# 🚨 launchd **不可**跑 `dart run`(2026-08-10 實機事故):`dart run` 每次
# 都會執行 build hooks,而 `package:sqlite3` 的 hook 會去 github.com 抓
# 預編譯二進位檔。開盤當下機器剛喚醒、Wi-Fi 未接上 → DNS 失敗 → process
# 在 main() 之前就死掉,**連心跳都發不出來**。當天 09:00–09:30 共 7 輪
# 完全沒有檢查任何提醒,而那是波動最大的時段。
#
# 編譯後執行期沒有 build hook,也就不依賴網路才能啟動;實測啟動時間
# 3.46s → 0.45s。
#
# 裝到 Application Support 而非 repo 的 build/:後者會被 `flutter clean`
# 清掉,那樣 job 會**靜默失效**(binary 不見了,launchd 只記一個非零
# 退出碼,沒有人會看)。
# ⚠️ 路徑**不可含空格**(2026-08-10 實機):第一版用
# `~/Library/Application Support/Daredevil/cli`,而 plist 的 ProgramArguments
# 是丟給 `zsh -c` 的字串、沒有引號 → 在空格處被切斷,job 當場壞掉。
# 用無空格路徑比在 XML 裡疊引號可靠。
CLI_DIR="$HOME/.daredevil/cli"
echo "編譯 CLI(執行期不再需要網路)..."
mkdir -p "$CLI_DIR"

# 建置標記(2026-08-15):產物落後 source 時,exit code、update_run、日誌
# 三個訊號全部正常,跑的卻是舊邏輯——實測落後 3 天,是靠檔案時間戳才撞
# 見的。把 SHA 寫進 bundle,讓每次執行的日誌自己就能回答「跑的是哪一版」。
#
# **dirty 一定要標**:working tree 有未 commit 的改動時,SHA 指的那份
# source 與實際編進去的**不是同一份**——不標記等於給出一個看起來精確、
# 實際錯誤的答案,比 unknown 更糟。
BUILD_SHA="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [ -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" ]; then
  BUILD_SHA="$BUILD_SHA-dirty"
fi
echo "建置標記:$BUILD_SHA"
for target in intraday_alert_check daily_update; do
  "$DART" build cli --target="bin/$target.dart" -o "build/cli/$target" >/dev/null 2>&1 || {
    echo "❌ 編譯 $target 失敗——請手動跑一次看錯誤:" >&2
    echo "   $DART build cli --target=bin/$target.dart -o build/cli/$target" >&2
    exit 1
  }
  rm -rf "$CLI_DIR/$target"
  cp -R "build/cli/$target/bundle" "$CLI_DIR/$target"
  [ -x "$CLI_DIR/$target/bin/$target" ] || { echo "❌ $target 產物不可執行" >&2; exit 1; }
  # 標記檔放 bundle 根,CLI 執行時由 buildStamp() 沿 resolvedExecutable 往上找
  echo "$BUILD_SHA" > "$CLI_DIR/$target/BUILD_INFO"

  # 用穩定身分簽章(2026-08-10 實機):`dart build cli` 的產物是 **ad-hoc**
  # 簽章,TCC 對它是按 cdhash 記授權——**每次重新編譯 cdhash 就變**,
  # macOS 會當成新程式再問一次「想要取用其他 App 的資料」。用開發者憑證
  # 簽過之後,TCC 認的是簽章身分,重編也不會重問。
  #
  # 找不到憑證就跳過(仍可運作,只是每次重編要重按一次允許),不讓它
  # 變成安裝失敗的理由。
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
  if [ -n "$IDENTITY" ]; then
    if codesign --force --sign "$IDENTITY" --timestamp=none \
         "$CLI_DIR/$target/bin/$target" >/dev/null 2>&1; then
      echo "     已簽章($IDENTITY)"
    else
      echo "     ⚠️ 簽章失敗,沿用 ad-hoc(重編後需重新授權一次)" >&2
    fi
  else
    echo "     ⚠️ 找不到開發者憑證,沿用 ad-hoc(重編後需重新授權一次)" >&2
  fi
  echo "  ✅ $CLI_DIR/$target/bin/$target"
done
if [ "$CLI_ONLY" = 1 ]; then
  echo "✅ CLI 已更新至 $BUILD_SHA(--cli-only,未動 launchd)"
  exit 0
fi

UID_NUM="$(id -u)"

# 路徑含空白或 shell 特殊字元會產生「plutil 過但 job 永遠死」的假成功
# (2026-08-08 二次審查 F7):寧可拒裝也不要裝一個假的
# `|` 是下方 sed 的分隔符、`;` 會在 plist 的 zsh -c 字串裡變成命令分隔符
# (2026-08-08 三次審查 F-4:前一版都沒擋)
case "$REPO$DART$HOME" in
  *[\ \'\"\&\<\>\$\`\|\;\(\)\*]*)
    echo "❌ 路徑含空白或特殊字元,plist 產生器不支援:" >&2
    echo "   REPO=$REPO" >&2
    echo "   DART=$DART" >&2
    echo "   HOME=$HOME" >&2
    exit 1
    ;;
esac

mkdir -p "$HOME/Library/Logs" "$HOME/Library/LaunchAgents"

for job in daily intraday; do
  src="$REPO/ops/launchd/com.neo.daredevil.$job.plist"
  dst="$HOME/Library/LaunchAgents/com.neo.daredevil.$job.plist"
  tmp="$(mktemp)"
  # 三類硬編碼路徑都要換:repo、dart、以及 $HOME 底下的日誌路徑
  # (只換前兩者的話,換機/換使用者時日誌會寫到別人的家目錄)
  sed -e "s|/Users/nealchen/IdeaProjects/daredevil|$REPO|g" \
      -e "s|__CLI__|$CLI_DIR|g" \
      -e "s|/opt/homebrew/bin/dart|$DART|g" \
      -e "s|/Users/nealchen/Library|$HOME/Library|g" "$src" > "$tmp"
  # 先驗證再落地:直接寫 dst 會在驗證失敗時留下半殘的 plist
  plutil -lint "$tmp" > /dev/null
  chmod 644 "$tmp"          # mktemp 產生 0600,保持與手裝時一致
  mv "$tmp" "$dst"
  launchctl bootout "gui/$UID_NUM/com.neo.daredevil.$job" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_NUM" "$dst"
  echo "✅ com.neo.daredevil.$job 已安裝 ($dst)"
done

echo
# 殘留檢查:找「不屬於本機 HOME 的硬編碼家目錄」。
# (2026-08-08 三次審查 F-3:前一版用 `grep -l | grep -v "^$HOME"`,而
#  grep -l 印的是**檔名**、必然位於 $HOME 底下,所以永遠被濾光——一個
#  標著「應無輸出」卻結構上不可能有輸出的檢查,正是它要防的假成功。)
residual=0
for f in "$HOME/Library/LaunchAgents/com.neo.daredevil."*.plist; do
  # 抓 /Users/<某人> 但不是自己的 HOME
  if grep -oE '/Users/[A-Za-z0-9._-]+' "$f" 2>/dev/null | grep -v "^$HOME\$" | grep -q .; then
    echo "⚠️  $f 仍含其他使用者的硬編碼路徑:"
    grep -oE '/Users/[A-Za-z0-9._-]+[^<"]*' "$f" | grep -v "^$HOME" | sort -u | sed 's/^/     /'
    residual=1
  fi
done
echo "驗證:launchctl print gui/$UID_NUM/com.neo.daredevil.intraday | grep -E 'runs|exit'"
echo "日誌:$HOME/Library/Logs/daredevil-*.log"

# 殘留必須讓腳本以非零結束(2026-08-08 三次審查 M-4):否則「裝好了」與
# 「裝好了但有殘留」的 exit code 相同,被 CI 或其他腳本呼叫時看不出差別。
if [ "$residual" -ne 0 ]; then
  echo "❌ 安裝完成,但偵測到殘留路徑(見上)——請確認後重跑" >&2
  exit 1
fi
echo "✅ 殘留檢查通過(無其他使用者的路徑)"
