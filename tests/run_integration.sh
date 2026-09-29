#!/bin/sh
# Headless mpv checks for pause/unpause behavior. Requires mpv, ffmpeg, and a
# Lua-capable mpv build. Run from the repo root.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUT=${TMPDIR:-/tmp}/gradual-pause-it
mkdir -p "$OUT"

ffmpeg -y -f lavfi -i "sine=frequency=440:duration=8" \
    -f lavfi -i "testsrc=size=160x120:rate=15:duration=8" \
    -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac "$OUT/long.mp4" \
    >"$OUT/ffmpeg-long.log" 2>&1
ffmpeg -y -f lavfi -i "sine=frequency=440:duration=1" \
    -f lavfi -i "color=c=black:s=64x64:r=10:d=1" \
    -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac "$OUT/short.mp4" \
    >"$OUT/ffmpeg-short.log" 2>&1

run_case() {
    name=$1
    media=$2
    shift 2
    result="$OUT/$name.txt"
    log="$OUT/$name.log"
    rm -f "$result"
    echo "== $name =="
    set +e
    GP_CASE=$name GP_RESULT=$result timeout 20 mpv --no-config --ao=null --vo=null \
        --volume=80 \
        --script="$ROOT/scripts/gradual_pause.lua" \
        --script="$ROOT/tests/integration.lua" \
        "$@" \
        "$media" \
        --msg-level=all=warn,gradual_pause=info,integration=info \
        >"$log" 2>&1
    status=$?
    set -e
    if [ ! -f "$result" ]; then
        echo "FAIL $name-no-result (mpv exit $status)" | tee -a "$OUT/summary.txt"
        echo "---- log ----"
        tail -n 40 "$log"
        return
    fi
    cat "$result"
    cat "$result" >> "$OUT/summary.txt"
}

rm -f "$OUT/summary.txt"
touch "$OUT/summary.txt"

run_case main "$OUT/long.mp4" \
    --script-opts=gradual_pause-debug_mode=yes
run_case key "$OUT/long.mp4" \
    --script-opts=gradual_pause-debug_mode=yes
run_case restore "$OUT/long.mp4" \
    --script-opts=gradual_pause-debug_mode=yes,gradual_pause-restore_position=yes
run_case eof "$OUT/short.mp4" \
    --keep-open=yes \
    --script-opts=gradual_pause-debug_mode=yes

if grep -q '^FAIL' "$OUT/summary.txt"; then
    echo "integration failed; logs in $OUT"
    exit 1
fi
echo "all integration cases passed"
