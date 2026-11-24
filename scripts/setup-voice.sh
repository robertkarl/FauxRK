#!/bin/sh
# Installs what RK dictation needs: whisper-cli (Homebrew whisper-cpp) and one
# local ggml model at ~/Library/Application Support/RK/whisper/ggml-model.bin.
# RK also finds existing models in ~/.cache/whisper-cpp and ~/models/whisper,
# or any path in RK_WHISPER_MODEL. Override the download with RK_WHISPER_MODEL_NAME.
set -eu

model_name="${RK_WHISPER_MODEL_NAME:-ggml-large-v3-turbo-q5_0.bin}"
model_dir="$HOME/Library/Application Support/RK/whisper"
model_path="$model_dir/ggml-model.bin"
model_url="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$model_name"

if ! command -v whisper-cli >/dev/null 2>&1; then
    echo "Installing whisper-cpp with Homebrew…"
    brew install whisper-cpp
fi

if [ -s "$model_path" ]; then
    echo "Model already installed: $model_path"
else
    mkdir -p "$model_dir"
    echo "Downloading $model_name…"
    curl -fL --progress-bar -o "$model_path.partial" "$model_url"
    mv "$model_path.partial" "$model_path"
fi

echo "Checking whisper-cli loads the model…"
probe="$(mktemp -d)"
trap 'rm -rf "$probe"' EXIT
say -o "$probe/probe.wav" --data-format=LEI16@16000 "RK dictation is ready."
whisper-cli -m "$model_path" -f "$probe/probe.wav" -nt -np
