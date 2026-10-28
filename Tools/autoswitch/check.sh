#!/bin/zsh
# Locks down engine behavior: rule-tagged cases, golden snapshots, Telex lock, metrics.
# usage: Tools/autoswitch/check.sh          (check)
#        Tools/autoswitch/check.sh update   (accept current behavior as the new golden)
set -e
cd "$(dirname "$0")"
E=../../Engine
SRC=($E/Engine.cpp $E/Vietnamese.cpp $E/SmartSwitchKey.cpp)
clang++ -std=c++17 -O2 -w ${=EXTRA} -I$E -I$E/platforms -o test/harness test/harness.cpp $SRC
clang++ -std=c++17 -O2 -w ${=EXTRA} -DAS_TESTING -I$E -I$E/platforms -o sim/sim sim/sim.cpp $SRC
rc=0
python3 rules/run_rules.py || rc=1
python3 rules/golden.py ${1:-check} || rc=1

# Engine/Driver (what the iOS keyboard runs): same output as the simulator, and fast enough
clang++ -std=c++17 -O2 -w ${=EXTRA} -I$E -I$E/platforms -o driver/drvlazy driver/drvlazy.cpp $E/Driver.cpp $SRC
clang++ -std=c++17 -O2 -w ${=EXTRA} -I$E -I$E/platforms -o driver/bench driver/bench.cpp $E/Driver.cpp $SRC
U=${TMPDIR:-/tmp}/vikey_check_chat.units
python3 sim/prep.py sim/corpus/chat_messages.txt > $U
(cd driver && ./cmp.sh $U | grep -q "whole text equal: True") && echo "driver == simulator: ok" || { echo "FAIL driver output differs from the simulator"; rc=1; }
# budget: ~6x the M-series Mac mini numbers (avg ~155 ns, p99.9 ~1.8 us), so slower CI machines still pass
driver/bench $U 1000 20000 && echo "performance: ok" || { echo "FAIL performance budget (Engine/Driver per key)"; rc=1; }
exit $rc
