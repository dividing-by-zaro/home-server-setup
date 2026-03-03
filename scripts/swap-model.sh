#!/usr/bin/env bash

# swap-model.sh — Stop the running llama.cpp server, download a new GGUF model
# from Hugging Face, and restart it as a persistent systemd service.
#
# Usage:
#   ./swap-model.sh                              # interactive picker from ~/models/
#   ./swap-model.sh <hf-repo> <gguf-filename>    # download from Hugging Face
#
# Example:
#   ./swap-model.sh
#   ./swap-model.sh unsloth/Qwen3.5-4B-GGUF Qwen3.5-4B-Q4_K_M.gguf
#   ./swap-model.sh unsloth/Qwen3.5-4B-GGUF Qwen3.5-4B-Q8_0.gguf --delete-old --ngl 28
#
# Options:
#   --delete-old    Remove the previously loaded model file
#   --port PORT     Server port (default: 8081)
#   --ctx  CTX      Context window size (default: 4096)
#   --ngl  NGL      Number of layers offloaded to GPU (default: 99)
#
# If the server fails to start, retries with progressively smaller context
# windows (halving each time, floor of 512).
#
# Requirements: llama.cpp built at ~/llama.cpp, hf CLI (pip install huggingface_hub)
# Models are stored in ~/models. Server binds to 0.0.0.0 — secure via firewall/VPN.

set -euo pipefail

LLAMA_SERVER="${HOME}/llama.cpp/build/bin/llama-server"
MODEL_DIR="${HOME}/models"
SERVICE_NAME="llama.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
PORT=8081
HOST="0.0.0.0"
CTX=16384
NGL=99
CTX_FLOOR=512

usage() {
    cat <<EOF
Usage: $(basename "$0") [<repo> <filename>] [options]

When run with no arguments, presents an interactive picker of models in ~/models/.

Arguments:
  repo        HF repo (e.g. unsloth/Qwen3.5-4B-GGUF)
  filename    GGUF file (e.g. Qwen3.5-4B-Q4_K_M.gguf)

Options:
  --delete-old    Delete previous model file
  --port PORT     Server port (default: $PORT)
  --ctx  CTX      Context size (default: $CTX)
  --ngl  NGL      GPU layers (default: $NGL)
  -h, --help      Show this help
EOF
    exit 0
}

# --- Determine mode: interactive picker vs HF download ---

SKIP_DOWNLOAD=false
DELETE_OLD=false
REPO=""
FILENAME=""

if [[ $# -eq 0 ]] || [[ "$1" == --* ]] || [[ "$1" == -h ]]; then
    # No positional args (or first arg is a flag) → interactive picker
    SKIP_DOWNLOAD=true

    models=()
    while IFS= read -r -d '' f; do
        models+=("$(basename "$f")")
    done < <(find "$MODEL_DIR" -maxdepth 1 -name '*.gguf' -type f -print0 2>/dev/null | sort -z)

    if [[ ${#models[@]} -eq 0 ]]; then
        echo "No .gguf files found in ${MODEL_DIR}/"
        echo "Download a model first: $(basename "$0") <repo> <filename>"
        exit 1
    fi

    echo "Available models in ${MODEL_DIR}/:"
    echo
    PS3=$'\nSelect a model (number): '
    select choice in "${models[@]}"; do
        if [[ -n "$choice" ]]; then
            FILENAME="$choice"
            echo
            echo "Selected: $FILENAME"
            break
        else
            echo "Invalid selection, try again."
        fi
    done
else
    # Positional args provided → HF download mode
    if [[ $# -lt 2 ]]; then
        echo "Error: repo and filename required"
        usage
    fi
    REPO="$1"; FILENAME="$2"; shift 2
fi

# --- Parse optional flags ---

while [[ $# -gt 0 ]]; do
    case "$1" in
        --delete-old) DELETE_OLD=true; shift ;;
        --port) PORT="$2"; shift 2 ;;
        --ctx)  CTX="$2"; shift 2 ;;
        --ngl)  NGL="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown: $1"; usage ;;
    esac
done

NEW_MODEL="${MODEL_DIR}/${FILENAME}"
CURRENT_USER=$(whoami)

OLD_MODEL=""
[[ -f "$SERVICE_FILE" ]] && OLD_MODEL=$(grep -oP '(?<=-m )\S+' "$SERVICE_FILE" 2>/dev/null || true)

# --- Stop current service ---

echo "▸ Stopping ${SERVICE_NAME}..."
systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null && sudo systemctl stop "$SERVICE_NAME" && echo "  Stopped." || echo "  Not running."
pgrep -x llama-server > /dev/null 2>&1 && { echo "▸ Killing stray processes..."; pkill -x llama-server || true; sleep 2; }

# --- Download model (skip if interactive picker was used) ---

if [[ "$SKIP_DOWNLOAD" == true ]]; then
    if [[ ! -f "$NEW_MODEL" ]]; then
        echo "Error: model file not found: ${NEW_MODEL}"
        exit 1
    fi
    echo "▸ Using local model: ${NEW_MODEL}"
else
    echo "▸ Downloading ${REPO} / ${FILENAME}..."
    mkdir -p "$MODEL_DIR"
    if [[ -f "$NEW_MODEL" ]]; then
        echo "  Already exists, skipping."
    else
        hf download "$REPO" --include "$FILENAME" --local-dir "$MODEL_DIR"
        if [[ ! -f "$NEW_MODEL" ]]; then
            FOUND=$(find "$MODEL_DIR" -name "$FILENAME" -type f 2>/dev/null | head -1)
            [[ -n "$FOUND" ]] && mv "$FOUND" "$NEW_MODEL" || { echo "Error: file not found after download"; exit 1; }
        fi
        echo "  Downloaded."
    fi
fi

# --- Delete old model if requested ---

if [[ "$DELETE_OLD" == true && -n "$OLD_MODEL" && -f "$OLD_MODEL" && "$OLD_MODEL" != "$NEW_MODEL" ]]; then
    echo "▸ Deleting old model: ${OLD_MODEL}"
    rm -f "$OLD_MODEL"
fi

# --- Build context size list: CTX, CTX/2, CTX/4, ... down to CTX_FLOOR ---

ctx_sizes=()
size=$CTX
while [[ $size -ge $CTX_FLOOR ]]; do
    ctx_sizes+=("$size")
    size=$((size / 2))
done
# Ensure the floor is included if halving skipped it
if [[ ${ctx_sizes[-1]} -ne $CTX_FLOOR && $CTX -gt $CTX_FLOOR ]]; then
    ctx_sizes+=("$CTX_FLOOR")
fi

# --- Retry loop: try each context size until one works ---

echo "▸ Starting service (will try context sizes: ${ctx_sizes[*]})..."

for try_ctx in "${ctx_sizes[@]}"; do
    SERVER_FLAGS=(--jinja -ngl "$NGL" --flash-attn on -np 1 -c "$try_ctx" --port "$PORT" --host "$HOST" --temp 0.6 --top-k 20 --top-p 0.95 --min-p 0 --reasoning-format deepseek)

    echo "  Trying -c ${try_ctx}..."

    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Llama.cpp Server
After=network.target

[Service]
Type=simple
User=${CURRENT_USER}
ExecStart=${LLAMA_SERVER} -m ${NEW_MODEL} ${SERVER_FLAGS[@]}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME" --quiet
    sudo systemctl start "$SERVICE_NAME"
    sleep 3

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "✓ Running at http://${HOST}:${PORT} with ${NEW_MODEL} (ctx=${try_ctx})"
        echo "  Logs: sudo journalctl -u ${SERVICE_NAME} -f"
        exit 0
    else
        echo "  Failed with -c ${try_ctx}."
        # Stop the failed service before retrying
        sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    fi
done

echo "✗ All context sizes failed. Check: sudo journalctl -u ${SERVICE_NAME} -n 30"
exit 1
