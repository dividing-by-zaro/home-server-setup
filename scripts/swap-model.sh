#!/usr/bin/env bash

# swap-model.sh — Stop the running llama.cpp server, download a new GGUF model
# from Hugging Face, and restart it as a persistent systemd service.
#
# Usage:
#   ./swap-model.sh <hf-repo> <gguf-filename> [options]
#
# Example:
#   ./swap-model.sh unsloth/Qwen3.5-4B-GGUF Qwen3.5-4B-Q4_K_M.gguf
#   ./swap-model.sh unsloth/Qwen3.5-4B-GGUF Qwen3.5-4B-Q8_0.gguf --delete-old --ngl 28
#
# Options:
#   --delete-old    Remove the previously loaded model file
#   --port PORT     Server port (default: 8081)
#   --ctx  CTX      Context window size (default: 4096)
#   --ngl  NGL      Number of layers offloaded to GPU (default: 99)
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
CTX=4096
NGL=99

SERVER_FLAGS=(
    --jinja
    -ngl "$NGL"
    --flash-attn on
    -np 1
    -c "$CTX"
    --port "$PORT"
    --host "$HOST"
    --temp 0.6
    --top-k 20
    --top-p 0.95
    --min-p 0
    --reasoning-format deepseek
)

usage() {
    cat <<EOF
Usage: $(basename "$0") <repo> <filename> [options]

Arguments:
  repo        HF repo (e.g. unsloth/Qwen3.5-4B-GGUF)
  filename    GGUF file (e.g. Qwen3.5-4B-Q4_K_M.gguf)

Options:
  --delete-old    Delete previous model file
  --port PORT     Server port (default: $PORT)
  --ctx  CTX      Context size (default: $CTX)
  --ngl  NGL      GPU layers (default: $NGL)
EOF
    exit 0
}

[[ $# -lt 2 ]] && { echo "Error: repo and filename required"; usage; }

REPO="$1"; FILENAME="$2"; shift 2
DELETE_OLD=false

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

SERVER_FLAGS=(--jinja -ngl "$NGL" --flash-attn on -np 1 -c "$CTX" --port "$PORT" --host "$HOST" --temp 0.6 --top-k 20 --top-p 0.95 --min-p 0 --reasoning-format deepseek)
NEW_MODEL="${MODEL_DIR}/${FILENAME}"
CURRENT_USER=$(whoami)

OLD_MODEL=""
[[ -f "$SERVICE_FILE" ]] && OLD_MODEL=$(grep -oP '(?<=-m )\S+' "$SERVICE_FILE" 2>/dev/null || true)

echo "▸ Stopping ${SERVICE_NAME}..."
systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null && sudo systemctl stop "$SERVICE_NAME" && echo "  Stopped." || echo "  Not running."
pgrep -x llama-server > /dev/null 2>&1 && { echo "▸ Killing stray processes..."; pkill -x llama-server || true; sleep 2; }

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

if [[ "$DELETE_OLD" == true && -n "$OLD_MODEL" && -f "$OLD_MODEL" && "$OLD_MODEL" != "$NEW_MODEL" ]]; then
    echo "▸ Deleting old model: ${OLD_MODEL}"
    rm -f "$OLD_MODEL"
fi

echo "▸ Writing ${SERVICE_FILE}..."
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

echo "▸ Starting service..."
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME" --quiet
sudo systemctl start "$SERVICE_NAME"
sleep 2

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "✓ Running at http://${HOST}:${PORT} with ${NEW_MODEL}"
    echo "  Logs: sudo journalctl -u ${SERVICE_NAME} -f"
else
    echo "✗ Failed. Check: sudo journalctl -u ${SERVICE_NAME} -n 30"
    exit 1
fi