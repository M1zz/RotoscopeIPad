#!/bin/zsh
# 아이폰 원본 스크린샷(6.9") 캡처 — 한 벌.
#
# 사용법: scripts/capture_iphone_screenshots.sh <시뮬레이터 UDID>   (iPhone 17 Pro Max 급)
#
# 준비: Debug 빌드를 그 시뮬레이터에 설치하고 scripts/make_sample_projects.py 로 예시 작품을 넣어 둔다.
# 결과: docs/screenshots/raw/iphone/NN-….png (1320x2868) — 그다음 make_marketing_screenshots.py
#
# 아이폰 화면에는 글자가 없다(그림 단추뿐이고 상태 막대도 시각만). 그래서 아이패드와 달리
# 언어마다 찍지 않고 한 벌을 모든 언어의 합성에 쓴다. 화면에 글자가 생기면 언어별로 바꾼다.
set -e
U=$1
APP=com.leeo.RotoscopeiPad
ROOT=${0:A:h:h}
OUT=$ROOT/docs/screenshots/raw/iphone
mkdir -p $OUT
xcrun simctl boot $U 2>/dev/null || true
xcrun simctl bootstatus $U >/dev/null
DOCS=$(xcrun simctl get_app_container $U $APP data)/Documents/Projects
xcrun simctl status_bar $U override --time 9:41 --batteryState charged --batteryLevel 100 \
  --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4

SCENES=(01-trace-bunny:bunny 02-trace-rocket:rocket 03-stamps-fish:fish 04-home:home)
project_dir() { python3 -c "import uuid;print(str(uuid.uuid5(uuid.NAMESPACE_URL,'palangbook-sample-$1')).upper())"; }
wait_s() { until false; do sleep $1; break; done; }

for scene in $SCENES; do
  name=${scene%%:*}; work=${scene##*:}
  xcrun simctl terminate $U $APP 2>/dev/null || true
  if [[ $work == home ]]; then
    xcrun simctl launch $U $APP -ScreenshotHome >/dev/null
  else
    touch $DOCS/$(project_dir $work)/project.json
    xcrun simctl launch $U $APP >/dev/null
  fi
  wait_s 6
  rm -f $OUT/$name.png   # simctl 은 있는 파일을 덮어쓰지 않고 실패한다
  xcrun simctl io $U screenshot --type=png $OUT/$name.png >/dev/null
  echo $name
done
