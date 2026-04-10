#!/bin/bash
# Configure local LLM providers (LMStudio, Ollama) and save to pi models config in container

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER="pi-agent"
PI_MODELS_PATH="/root/.pi/agent/models.json"

# ── helpers ────────────────────────────────────────────────────────────────────

show_menu() {
    clear
    echo
    echo "  local provider configuration"
    echo "  ============================"
    echo
    echo "  [1] Configure LMStudio"
    echo "  [2] Configure Ollama"
    echo "  [3] View current config"
    echo "  [4] Clear all providers"
    echo "  [Q] Done"
    echo
}

assert_container_running() {
    local state
    state="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)"
    if [[ "$state" != "true" ]]; then
        echo "  Container '$CONTAINER' is not running. Start it first."
        return 1
    fi
    return 0
}

read_or_default() {
    local prompt="$1"
    local default="$2"
    local value
    read -r -p "$prompt" value
    if [[ -z "$value" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

get_current_config() {
    docker exec "$CONTAINER" cat "$PI_MODELS_PATH" 2>/dev/null || echo "{}"
}

# ── configure LMStudio ─────────────────────────────────────────────────────────

configure_lmstudio() {
    assert_container_running || return 0

    clear
    echo
    echo "  ⚠️  LMStudio Configuration"
    echo "  ====================="
    echo
    echo "  WARNING: LMStudio must be running on your system for setup to work."
    echo "  LMStudio typically runs on http://localhost:1234/v1"
    echo
    echo "  NOTE: If LMStudio runs on your host machine (not in the container),"
    echo "  use http://host.docker.internal:1234/v1 on Docker Desktop (Windows/Mac)"
    echo "  or http://<your-host-ip>:1234/v1 on Linux."
    echo
    echo "  Provide the API endpoint where LMStudio is accessible FROM THE CONTAINER."
    echo

    local url
    url=$(read_or_default "  API URL (default http://host.docker.internal:1234/v1): " "http://host.docker.internal:1234/v1")
    echo
    echo "  Fetching available models from LMStudio..."

    # Poll LMStudio for available models
    local models_json
    models_json=$(curl -s "$url/models" 2>/dev/null || echo "")

    if [[ -z "$models_json" ]] || ! echo "$models_json" | jq . > /dev/null 2>&1; then
        echo "  ✗ Could not reach LMStudio at $url"
        echo "  Make sure it's running and accessible."
        return 1
    fi

    # Parse available models
    mapfile -t available_models < <(echo "$models_json" | jq -r '.data[].id // .data[] | objects | .id // empty' 2>/dev/null | sort)

    if (( ${#available_models[@]} == 0 )); then
        echo "  ✗ No models found. Load a model in LMStudio first."
        return 1
    fi

    echo
    echo "  Available models:"
    local i=1
    for model in "${available_models[@]}"; do
        printf "  [%d] %s\n" "$i" "$model"
        ((i++))
    done

    echo
    echo "  Enter numbers to add, separated by spaces or commas (e.g. 1 3)."
    read -r -p "  Selection (blank to cancel): " raw
    [[ -z "$raw" ]] && return 0

    raw="${raw//,/ }"
    local -a selected_models=()
    local idx
    for token in $raw; do
        if [[ "$token" =~ ^[0-9]+$ ]]; then
            idx=$((token - 1))
            if (( idx >= 0 && idx < ${#available_models[@]} )); then
                selected_models+=("${available_models[$idx]}")
            else
                echo "  Skipping invalid index: $token"
            fi
        fi
    done

    if (( ${#selected_models[@]} == 0 )); then
        echo "  No valid models selected."
        return 1
    fi

    # Build the provider config
    local config
    config=$(get_current_config)
    [[ "$config" == "{}" ]] && config="{\"providers\": {}}"

    # Build models array
    local models_array="["
    for i in "${!selected_models[@]}"; do
        [[ $i -gt 0 ]] && models_array="$models_array,"
        models_array="$models_array{\"id\": \"${selected_models[$i]}\"}"
    done
    models_array="$models_array]"

    # Add provider with selected models
    config=$(echo "$config" | jq ".providers.lmstudio = {\"baseUrl\": \"$url\", \"api\": \"openai-completions\", \"apiKey\": \"lmstudio\", \"models\": $models_array}")

    # Ensure directory exists and save
    echo "$config" | docker exec -i "$CONTAINER" bash -c "mkdir -p $(dirname $PI_MODELS_PATH) && cat > $PI_MODELS_PATH"

    echo
    echo "  ✅ LMStudio configuration saved with ${#selected_models[@]} model(s)."
    echo
}

# ── configure Ollama ──────────────────────────────────────────────────────────

configure_ollama() {
    assert_container_running || return 0

    clear
    echo
    echo "  ⚠️  Ollama Configuration"
    echo "  ====================="
    echo
    echo "  WARNING: Ollama must be running on your system for setup to work."
    echo "  Ollama typically runs on http://localhost:11434/v1"
    echo
    echo "  NOTE: If Ollama runs on your host machine (not in the container),"
    echo "  use http://host.docker.internal:11434/v1 on Docker Desktop (Windows/Mac)"
    echo "  or http://<your-host-ip>:11434/v1 on Linux."
    echo
    echo "  Provide the API endpoint where Ollama is accessible FROM THE CONTAINER."
    echo

    local url
    url=$(read_or_default "  API URL (default http://host.docker.internal:11434/v1): " "http://host.docker.internal:11434/v1")
    echo
    echo "  Fetching available models from Ollama..."

    # Poll Ollama for available models
    local models_json
    models_json=$(curl -s "$url/models" 2>/dev/null || echo "")

    if [[ -z "$models_json" ]] || ! echo "$models_json" | jq . > /dev/null 2>&1; then
        echo "  ✗ Could not reach Ollama at $url"
        echo "  Make sure it's running and accessible."
        return 1
    fi

    # Parse available models
    mapfile -t available_models < <(echo "$models_json" | jq -r '.data[].id // .data[] | objects | .id // empty' 2>/dev/null | sort)

    if (( ${#available_models[@]} == 0 )); then
        echo "  ✗ No models found. Pull a model in Ollama first (e.g. ollama pull llama2)."
        return 1
    fi

    echo
    echo "  Available models:"
    local i=1
    for model in "${available_models[@]}"; do
        printf "  [%d] %s\n" "$i" "$model"
        ((i++))
    done

    echo
    echo "  Enter numbers to add, separated by spaces or commas (e.g. 1 3)."
    read -r -p "  Selection (blank to cancel): " raw
    [[ -z "$raw" ]] && return 0

    raw="${raw//,/ }"
    local -a selected_models=()
    local idx
    for token in $raw; do
        if [[ "$token" =~ ^[0-9]+$ ]]; then
            idx=$((token - 1))
            if (( idx >= 0 && idx < ${#available_models[@]} )); then
                selected_models+=("${available_models[$idx]}")
            else
                echo "  Skipping invalid index: $token"
            fi
        fi
    done

    if (( ${#selected_models[@]} == 0 )); then
        echo "  No valid models selected."
        return 1
    fi

    # Build the provider config
    local config
    config=$(get_current_config)
    [[ "$config" == "{}" ]] && config="{\"providers\": {}}"

    # Build models array
    local models_array="["
    for i in "${!selected_models[@]}"; do
        [[ $i -gt 0 ]] && models_array="$models_array,"
        models_array="$models_array{\"id\": \"${selected_models[$i]}\"}"
    done
    models_array="$models_array]"

    # Add provider with selected models
    config=$(echo "$config" | jq ".providers.ollama = {\"baseUrl\": \"$url\", \"api\": \"openai-completions\", \"apiKey\": \"ollama\", \"models\": $models_array}")

    # Ensure directory exists and save
    echo "$config" | docker exec -i "$CONTAINER" bash -c "mkdir -p $(dirname $PI_MODELS_PATH) && cat > $PI_MODELS_PATH"

    echo
    echo "  ✅ Ollama configuration saved with ${#selected_models[@]} model(s)."
    echo
}

# ── view current config ────────────────────────────────────────────────────────

view_config() {
    assert_container_running || return 0

    clear
    echo
    echo "  Current Provider Configuration"
    echo "  ============================"
    echo

    local config
    config=$(docker exec "$CONTAINER" cat "$PI_MODELS_PATH" 2>/dev/null || echo "")

    if [[ -z "$config" ]]; then
        echo "  No custom providers configured yet."
        echo "  (File: $PI_MODELS_PATH)"
    else
        echo "$config" | jq '.' 2>/dev/null || echo "$config"
    fi
    echo
}

# ── clear all providers ────────────────────────────────────────────────────────

clear_providers() {
    assert_container_running || return 0

    read -r -p "  Clear all provider configurations? (y/N): " confirm
    if [[ "${confirm^^}" != "Y" ]]; then
        echo "  Canceled."
        return 0
    fi

    docker exec "$CONTAINER" bash -c "mkdir -p $(dirname $PI_MODELS_PATH) && echo '{}' > $PI_MODELS_PATH"
    echo "  ✅ All provider configurations cleared."
    echo
}

# ── main loop ──────────────────────────────────────────────────────────────────

while true; do
    show_menu
    read -r -p "  Select an option: " choice
    choice="${choice^^}"
    echo

    case "$choice" in
        1) configure_lmstudio ;;
        2) configure_ollama ;;
        3) view_config ;;
        4) clear_providers ;;
        Q) echo "  Done."; exit 0 ;;
        *) echo "  Unknown option." ;;
    esac

    if [[ "$choice" != "Q" ]]; then
        read -r -p "  Press Enter to continue"
    fi
done
