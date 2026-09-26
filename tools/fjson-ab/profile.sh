#!/bin/bash
# usage (repo root, after `cjpm bench` built it): tools/fjson-ab/profile.sh 'Class.case' OUT
# Runs one bench of fjson's test binary and samples it (macOS `sample`) for 3 s; prints the hottest frames.
set -e
bin=target/release/unittest_bin/fjson
DYLD_LIBRARY_PATH="$CANGJIE_HOME/runtime/lib/darwin_aarch64_cjnative:$CANGJIE_HOME/tools/lib" cjHeapSize=4GB "$bin" --bench --no-progress "--filter=$1" > "$2.run" 2>&1 &
pid=$!
sleep 1.5
sample "$pid" 3 -file "$2" > /dev/null 2>&1
wait "$pid" || true
grep -A40 'Sort by top of stack' "$2"
