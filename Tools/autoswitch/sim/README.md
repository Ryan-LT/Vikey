# Mixed-text typing simulator

Types a mixed Vietnamese/English corpus into the real engine, key by key, and measures how
often the user still has to switch language by hand.

## Corpora

- `corpus/chat_messages.txt`: 1,869 chat-style messages (21k words), generated with `corpus/gen_chat.py`.
- Viblo tech articles (269k words): not committed (third-party content). Recreate with
  `corpus/fetch_viblo.py` then `corpus/clean_viblo.py`.

## Run

```sh
python3 prep.py corpus/chat_messages.txt > chat.units      # Telex keystrokes, varied tone positions
E=../../../Sources/OpenKey/engine
clang++ -std=c++17 -O2 -w -DAS_TESTING -I$E -I$E/platforms -o sim sim.cpp $E/Engine.cpp $E/Vietnamese.cpp $E/Macro.cpp $E/SmartSwitchKey.cpp $E/ConvertTool.cpp
./sim chat.units            # ideal user: switches by hand only when the next word would come out wrong
./sim chat.units --lazy     # never switches by hand: wrong words per message
./sim chat.units --off      # auto switch off (baseline)
```

Compile-time variants for experiments: `-DAS_NO_LOOKBACK`, `-DAS_RESTORE_UNKNOWN=0`, `-DAS_DOUBLE_KEEP`.
