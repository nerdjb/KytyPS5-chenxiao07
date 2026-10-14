#!/bin/bash
# Production switch set for Demon's Souls (from run-windows.json) + best binary.
# Work in the repository root when this is the checked-out script (tools/local/), else in the folder
# of a packaged copy (the executable next to it).
_kyty_here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
if [ -d "$_kyty_here/../../_Build" ]; then cd "$_kyty_here/../.." || exit 1
elif [ -d "$_kyty_here/../_Build" ]; then cd "$_kyty_here/.." || exit 1
else cd "$_kyty_here" || exit 1; fi
export KYTY_SHADER_WARMUP=1
export KYTY_GPU_BUFFER_PAGES=1
export KYTY_RECORDING_CPUS=auto
export KYTY_SRT_NATIVE=1
export KYTY_SRT_PREDICATES=1
export KYTY_PREPARATION_SCRATCH=1
export KYTY_PREPARATION_LOOKUP=1
export KYTY_PREPARATION_TRIM=1
export KYTY_SPECIALIZATION_GUARD=1
export KYTY_PIPELINE_INDEX=1
export KYTY_BINDING_SCRATCH=1
export KYTY_DRAW_RUN_RANGES=1
export KYTY_BUFFER_RESIDENCY=1
export KYTY_COPY_FEEDBACK=1
export KYTY_ASYNC_LOD_STATS=1
export KYTY_BACKING_READ=1
export KYTY_STREAM_UPLOAD=1
export KYTY_FRAME_PIPELINE=1
export KYTY_IMAGE_BARRIER_DEDUPE=1
export KYTY_IMAGE_POOL=1
export KYTY_PENDING_DRAIN=1
export KYTY_DISPATCH_BATCH=128
export KYTY_VULKAN_RECORDING=1
export KYTY_DEFERRED_SUBMIT=1
export KYTY_NATIVE_XPR=1
export KYTY_WRITE_WINDOW_HANDOFF=1
export KYTY_READBACK_DETACH=1
export KYTY_ASYNC_WRITE_READBACK=1
export KYTY_READBACK_SLOTS=1
export KYTY_ASYNC_UPLOAD=2
export KYTY_BDA_DIRTY_REGIONS=1
export KYTY_GLOBAL_BARRIER_DEDUPE=1
export KYTY_RANGE_SET_FAST=1
export KYTY_IMAGE_GRANULES=2
export KYTY_NATIVE_XPR_PREDICT=1
export KYTY_NATIVE_IMAGE_PROOF=1
export KYTY_TEXTURE_RESOLVE_PAGES=1
export KYTY_ASYNC_REPROTECT=1
export KYTY_READBACK_NARROW=1
export KYTY_SHADER_WARMUP_THREADS=16
export KYTY_READBACK_QUEUE=1
export KYTY_TABLE_XPR=2
export KYTY_TABLE_DISPATCH=1
# The game renders 2560x1440 internally and downsamples into the 1080p window. Rendering at the
# output resolution instead cuts GPU pixel work ~1.8x with no visible change (the window shows 1080p
# either way). 900 = 1600x900 -> 1080p for more fps; 1440 restores the original behavior.
export KYTY_RENDER_HEIGHT=${KYTY_RENDER_HEIGHT:-1080}
# Live VRAM-budget GC: texture/buffer collection thresholds follow the current device-memory budget
# (prints KYTYGCBUDGET lines) instead of fixed startup values.
export KYTY_GC_LIVE_BUDGET=1
# KYTY_PIPELINE_FAST_BUILD=1: first compile of a new pipeline is unoptimized
# (VK_PIPELINE_CREATE_DISABLE_OPTIMIZATION_BIT), the optimized one is built on a worker, so the
# render thread is not blocked and a scene that keeps meeting new pipelines keeps its frame rate.
# A/B on this machine (Demon's Souls, 1080p, same route): p50 19.5 ms (~51 fps) with 1 vs 23.8 ms
# (~43 fps) with 0. The old RDNA2 startup-crash note does not apply to the RX 9070 (RDNA4) here.
# Set 0 to restore the optimized-first behaviour.
export KYTY_PIPELINE_FAST_BUILD=${KYTY_PIPELINE_FAST_BUILD:-1}
# Name every >100 ms stall in the log (frames, shader translations, pipeline creations, image
# uploads): turns "the hang" into "what the hang was", for attribution and verification.
export KYTY_HITCH_LOG_MS=${KYTY_HITCH_LOG_MS:-100}
# Cap the live GC budget at 10 GiB so texture/buffer collection starts earlier and keeps the
# resident set below the VRAM cap with room to absorb level-load bursts (softens the evict/upload
# storms that froze frames at ~12.7 GB of a ~12-14 GB budget). 0 = uncapped.
export KYTY_GC_BUDGET_CAP_MB=${KYTY_GC_BUDGET_CAP_MB:-10240}
# GPU render thread pinned off CPU 0 (interrupt-heavy); physical cores 1-7.
export KYTY_RENDER_CPUS=${KYTY_RENDER_CPUS:-"1,2,3,4,5,6,7"}
# Capture a fresh frame-interval (flips) file every ~12 s so a session can be analysed afterwards.
export KYTY_LIVE_FILE=${KYTY_LIVE_FILE:-/mnt/AI/tmp/opencode/flips-live.txt}
BIN="${KYTY_BIN:-./_Build/linux-nt/kyty_emulator}"
# A packaged copy has the executable next to the script.
[ -x "$BIN" ] || [ ! -x "./kyty_emulator" ] || BIN="./kyty_emulator"
# NOTE: default is the current (linux-nt) build, NOT the stale Oct 7 _Build/linux one.
# Hands-off stutter capture (KYTY_LIVE_FILE): a fresh frame-interval (flips) file every ~12 s.
# The game writes the last 3000 presented-frame intervals (us) per file, so any hitch is recorded
# without sending any input. Analyse with tools/local/stutter-report.py (or manually).
# System monitor for the stutter diagnosis: 1 Hz memory / swap / PSI-memory.
(
  while :; do
    pid=$(pgrep -x kyty_emulator | head -1)
    rss=0; [ -n "$pid" ] && rss=$(awk '/VmRSS/{print $2}' /proc/$pid/status 2>/dev/null)
    read -r avail swt swf < <(awk '/MemAvailable/{a=$2}/SwapTotal/{t=$2}/SwapFree/{f=$2}END{print a,t,f}' /proc/meminfo)
    psi=$(awk -F'avg10=' '/^some/{split($2,x," ");print x[1]}' /proc/pressure/memory 2>/dev/null)
    printf '%s rss_mb=%d avail_mb=%d swap_used_mb=%d psi_mem=%s\n' "$(date +%H:%M:%S)" \
      "$((rss/1024))" "$((avail/1024))" "$(( (swt-swf)/1024 ))" "$psi"
    sleep 1
  done
) > /mnt/AI/tmp/opencode/monitor9.log 2>&1 &
MON_PID=$!
FLIP_PID=""
if [ -n "$KYTY_LIVE_FILE" ]; then
  mkdir -p /mnt/AI/tmp/opencode/flips
  printf 'id 0\n' > "$KYTY_LIVE_FILE"
  (
    sleep 6; n=0
    while :; do
      n=$((n+1))
      printf 'id %d\nflips 3000 /mnt/AI/tmp/opencode/flips/%05d_%s.txt\n' "$n" "$n" "$(date +%H%M%S)" \
        > "$KYTY_LIVE_FILE.tmp" && mv "$KYTY_LIVE_FILE.tmp" "$KYTY_LIVE_FILE"
      sleep 12
    done
  ) &
  FLIP_PID=$!
fi
# Mailbox = vblank-aligned, no tearing, low latency (smooth). Override with PRESENT_MODE=Fifo|Immediate.
# MANGO=1 (default): MangoHud FPS/CPU/GPU overlay; MANGO=0 disables it.
# The game: KYTY_GAME, else Demon's Souls where it is installed here. (The apostrophe cannot sit
# inside a ${KYTY_GAME:-...} default: bash reads it as an opening quote.)
GAME="${KYTY_GAME:-}"
[ -n "$GAME" ] || GAME="/mnt/4tb/REtro/ps5/Demon's Souls.zar"
RUN=("$BIN")
if [ "${MANGO:-1}" = 1 ] && command -v mangohud >/dev/null 2>&1; then
  RUN=(mangohud "$BIN")
fi
# The helper loops above must die with the emulator: without this, every launch leaks one monitor and
# one flips writer that keep rewriting the same monitor9.log / flips-live.txt (and accumulate). No
# exec, so the trap can run.
cleanup() {
  [ -z "$MON_PID" ] || kill "$MON_PID" 2>/dev/null
  [ -z "$FLIP_PID" ] || kill "$FLIP_PID" 2>/dev/null
  return 0
}
trap cleanup EXIT
trap 'exit 130' INT TERM
# The emulator's diagnostics go to stdout (KYTY_HITCH_LOG_MS stall lines, [Trophy] load/unlock,
# KYTYGCBUDGET, errors) and a terminal scrolls them away. Keep a file per session plus a stable
# "last" symlink, so "check the log" after playing is possible (both writers fflush every line).
KYTY_LOG="${KYTY_LOG:-/mnt/AI/tmp/opencode/emulator-$(date +%Y%m%d-%H%M%S).log}"
mkdir -p "$(dirname "$KYTY_LOG")"
ln -sfn "$KYTY_LOG" "$(dirname "$KYTY_LOG")/emulator-last.log"
printf 'log: %s\n' "$KYTY_LOG"
"${RUN[@]}" --game "$GAME" \
  --screen-width 1920 --screen-height 1080 --console-language 1 \
  --shader-validation false --shader-log-direction Silent --printf-direction Silent \
  --vblank-frequency 60 --present-mode "${PRESENT_MODE:-Mailbox}" "$@" 2>&1 | tee "$KYTY_LOG"
exit "${PIPESTATUS[0]}"