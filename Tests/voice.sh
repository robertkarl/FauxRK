#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/tmp
work=$(mktemp -d "$PWD/build/tmp/voice.XXXXXX")
export TMPDIR="$work"
trap 'rm -rf "$work"' EXIT
say -o "$work/speech.wav" --data-format=LEI16@16000 'Please inspect the green building.'
xcrun clang -fobjc-arc -fmodules -Wall -I Sources -framework Cocoa -framework AVFoundation \
  Tests/voice.m Sources/RKVoice.m -o "$work/voice-tests"
cat > "$work/whisper-fixture" <<'SH'
#!/bin/sh
set -eu
while [ "$#" -gt 0 ]; do
    case "$1" in
        -f) input=$2; shift 2 ;;
        -of) output=$2; shift 2 ;;
        *) shift ;;
    esac
done
cmp "$input" "$RK_VOICE_FIXTURE"
printf '%s\n' 'Please inspect the green building.' > "$output.txt"
SH
chmod +x "$work/whisper-fixture"
touch "$work/model.bin"
RK_WHISPER_CLI="$work/whisper-fixture" RK_WHISPER_MODEL="$work/model.bin" \
  RK_VOICE_FIXTURE="$work/speech.wav" "$work/voice-tests" "$work/speech.wav"

# Opt into real local inference using RK's production CLI and model discovery.
if [ "${RK_TEST_LOCAL_WHISPER:-0}" = 1 ]; then
    "$work/voice-tests" "$work/speech.wav" real
fi
