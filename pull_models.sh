#!/bin/bash
# ---------------------------------------------------------------
# pull_models.sh — Read local_models from config.ini and pull each
#
# Modes:
#   --build   : Start/stop its own Ollama server (for Docker build)
#   --runtime : Assume Ollama is already running (for container start)
# ---------------------------------------------------------------
set -e

MODE="${1:---runtime}"
CONFIG_FILE="${2:-/opt/config.ini}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[pull_models] No config file found at $CONFIG_FILE — skipping model pull."
    exit 0
fi

# Parse local_models from the [ollama] section
MODELS=$(python3 -c "
import configparser, sys
cfg = configparser.ConfigParser()
cfg.read('$CONFIG_FILE')
print(cfg.get('ollama', 'local_models', fallback=''))
" 2>/dev/null || echo "")

if [ -z "$MODELS" ]; then
    echo "[pull_models] No local_models defined in config — skipping model pull."
    exit 0
fi

# In build mode, start our own Ollama server
OLLAMA_PID=""
if [ "$MODE" = "--build" ]; then
    echo "[pull_models] Starting Ollama server (build mode)..."
    ollama serve > /opt/logs/ollama_build_serve.log 2>&1 &
    OLLAMA_PID=$!
    sleep 5
fi

# Pull each model (comma-separated list), skip if already present
EXISTING=$(ollama list 2>/dev/null | awk 'NR>1 {print $1}' || echo "")

IFS=',' read -ra MODEL_ARRAY <<< "$MODELS"
for model in "${MODEL_ARRAY[@]}"; do
    model=$(echo "$model" | xargs)  # trim whitespace
    if [ -z "$model" ]; then
        continue
    fi
    if echo "$EXISTING" | grep -qx "$model"; then
        echo "[pull_models] Model already installed: $model"
    else
        echo "[pull_models] Pulling model: $model"
        ollama pull "$model" 2>&1 | tee "/opt/logs/pull_${model//[:\/]/_}.log"
    fi
done

# In build mode, stop the server we started
if [ -n "$OLLAMA_PID" ]; then
    kill $OLLAMA_PID
    wait $OLLAMA_PID 2>/dev/null || true
fi

echo "[pull_models] Done."
