#!/bin/zsh
# 앱 내 구입 심사용 스크린샷 — 어른 확인을 지난 결제 화면 (아이패드 13", 2064x2752).
#
# 사용법: scripts/capture_paywall_screenshot.sh <시뮬레이터 UDID> [로케일:가격 ...]
#         (없으면 en-US:\$9.99 ko:₩9,900)
#
# 준비: Debug 빌드를 그 시뮬레이터에 설치한다. 상품이 아직 App Store Connect 에 없어
#       시뮬레이터가 가격을 못 불러오므로, Debug 전용 -ScreenshotPaywall 인자로 가격을 준다.
# 결과: docs/screenshots/iap-review/<로케일>.png → App Store Connect ▸ 인앱 구입 ▸ 심사 정보
set -e
U=$1; shift
SHOTS=(en-US:\$9.99 ko:₩9,900)
(( $# )) && SHOTS=("$@")
APP=com.leeo.RotoscopeiPad
ROOT=${0:A:h:h}
OUT=$ROOT/docs/screenshots/iap-review
mkdir -p $OUT

typeset -A LANG_OF LOCALE_OF
LANG_OF=(ko ko en-US en ja ja zh-Hans zh-Hans zh-Hant zh-Hant es-MX es-MX de-DE de fr-FR fr pt-BR pt-BR it it)
LOCALE_OF=(ko ko_KR en-US en_US ja ja_JP zh-Hans zh_CN zh-Hant zh_TW es-MX es_MX de-DE de_DE fr-FR fr_FR pt-BR pt_BR it it_IT)
plist=~/Library/Developer/CoreSimulator/Devices/$U/data/Library/Preferences/.GlobalPreferences.plist

for shot in $SHOTS; do
  loc=${shot%%:*}; price=${shot#*:}
  xcrun simctl shutdown $U 2>/dev/null || true
  plutil -replace AppleLanguages -json "[\"${LANG_OF[$loc]}\"]" $plist
  plutil -replace AppleLocale -string ${LOCALE_OF[$loc]} $plist
  xcrun simctl boot $U
  xcrun simctl bootstatus $U >/dev/null
  sleep 8
  xcrun simctl ui $U appearance light   # 다크 모드로 바뀌어 있으면 장마다 색이 달라진다
  xcrun simctl status_bar $U override --time 9:41 --batteryState charged --batteryLevel 100 \
    --wifiMode active --wifiBars 3 --cellularMode notSupported
  # 앱별 언어 설정이 남아 있으면 시스템 언어를 무시하므로 인자로 못 박는다
  xcrun simctl launch $U $APP -AppleLanguages "(${LANG_OF[$loc]})" -AppleLocale ${LOCALE_OF[$loc]} \
    -ScreenshotPaywall "$price" >/dev/null
  sleep 6
  rm -f $OUT/$loc.png   # simctl 은 있는 파일을 덮어쓰지 않고 실패한다
  xcrun simctl io $U screenshot --type=png $OUT/$loc.png >/dev/null
  xcrun simctl terminate $U $APP 2>/dev/null || true
  echo "$loc $price → $OUT/$loc.png"
done
