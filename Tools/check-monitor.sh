#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:-/tmp/siliconpulse-monitor-qa}"
./build.sh
./SiliconPulse.app/Contents/MacOS/SiliconPulse "--monitor-qa=$output" > "$output.log" 2>&1
cat "$output/QA.txt"
printf '\nLocal renders: %s\n' "$output"
