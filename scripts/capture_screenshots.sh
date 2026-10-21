#!/bin/zsh
# 언어별 원본 스크린샷(아이패드 13") 캡처.
#
# 사용법: scripts/capture_screenshots.sh <시뮬레이터 UDID> [스토어 로케일 ...]   (없으면 전부)
#
# 준비: Debug 빌드를 그 시뮬레이터에 설치하고(홈 화면은 Debug 전용 -ScreenshotHome 인자로 연다)
#       scripts/make_sample_projects.py 로 예시 작품을 넣어 둔다.
# 결과: docs/screenshots/raw/<로케일>/NN-….png (2064x2752) — 그다음 make_marketing_screenshots.py
#
# 앱은 마지막으로 고친 작품을 열고 시작하므로, project.json 시각을 바꿔 장면을 고른다.
# 상태 막대의 날짜까지 그 언어로 나오도록 언어마다 시뮬레이터를 다시 켠다.
set -e
U=$1; shift
LOCALES=(ko en-US ja zh-Hans zh-Hant es-MX de-DE fr-FR pt-BR it en-GB ru th vi cs da el fi id nb)
(( $# )) && LOCALES=("$@")
APP=com.leeo.RotoscopeiPad
ROOT=${0:A:h:h}
xcrun simctl boot $U 2>/dev/null || true
xcrun simctl bootstatus $U >/dev/null
DOCS=$(xcrun simctl get_app_container $U $APP data)/Documents/Projects

# 스토어 로케일 → 시뮬레이터 언어 · 지역
typeset -A LANG_OF LOCALE_OF
LANG_OF=(ko ko en-US en ja ja zh-Hans zh-Hans zh-Hant zh-Hant es-MX es-MX de-DE de fr-FR fr pt-BR pt-BR it it en-GB en-GB ru ru th th vi vi cs cs da da el el fi fi id id nb nb)
LOCALE_OF=(ko ko_KR en-US en_US ja ja_JP zh-Hans zh_CN zh-Hant zh_TW es-MX es_MX de-DE de_DE fr-FR fr_FR pt-BR pt_BR it it_IT en-GB en_GB ru ru_RU th th_TH vi vi_VN cs cs_CZ da da_DK el el_GR fi fi_FI id id_ID nb nb_NO)

# 장면: 파일 이름 → 열 작품 (make_sample_projects.py 의 이름)
SCENES=(01-trace-bunny:bunny 02-trace-rocket:rocket 03-stamps-fish:fish 04-home:home)

project_dir() { python3 -c "import uuid;print(str(uuid.uuid5(uuid.NAMESPACE_URL,'palangbook-sample-$1')).upper())"; }
wait_s() { until false; do sleep $1; break; done; }

for loc in $LOCALES; do
  out=$ROOT/docs/screenshots/raw/$loc
  mkdir -p $out
  xcrun simctl shutdown $U 2>/dev/null || true
  plist=~/Library/Developer/CoreSimulator/Devices/$U/data/Library/Preferences/.GlobalPreferences.plist
  plutil -replace AppleLanguages -json "[\"${LANG_OF[$loc]}\"]" $plist
  plutil -replace AppleLocale -string ${LOCALE_OF[$loc]} $plist
  xcrun simctl boot $U
  xcrun simctl bootstatus $U >/dev/null
  wait_s 8
  xcrun simctl status_bar $U override --time 9:41 --batteryState charged --batteryLevel 100 \
    --wifiMode active --wifiBars 3 --cellularMode notSupported
  for scene in $SCENES; do
    name=${scene%%:*}; work=${scene##*:}
    xcrun simctl terminate $U $APP 2>/dev/null || true
    if [[ $work == home ]]; then
      xcrun simctl launch $U $APP -ScreenshotHome >/dev/null
    else
      touch $DOCS/$(project_dir $work)/project.json
      xcrun simctl launch $U $APP >/dev/null
    fi
    wait_s 5
    rm -f $out/$name.png   # simctl 은 있는 파일을 덮어쓰지 않고 실패한다
    xcrun simctl io $U screenshot --type=png $out/$name.png >/dev/null
    echo "$loc $name"
  done
done
