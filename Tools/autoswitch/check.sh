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
exit $rc
