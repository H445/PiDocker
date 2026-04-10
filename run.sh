#!/bin/bash
# Interactive menu to manage the pi-agent container

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER="pi-agent"
EXT_EXAMPLES="/usr/local/lib/node_modules/@mariozechner/pi-coding-agent/examples/extensions"
EXT_USER="/root/.pi/extensions"
SELECTED_EXTENSIONS=()

show_menu() {
    clear
    echo
    echo "  pi-agent  --  management menu"
    echo "  ================================"
    echo
    echo "  [1] Launch pi                 (launch.sh)"
    echo "  [2] Launch pi with extensions"
    echo "  [3] Build image               (build.sh)"
    echo "  [4] Backup data               (backup.sh)"
    echo "  [5] Restore data              (restore.sh)"
    echo "  [6] Stop container"
    echo "  [7] Remove container"
    echo "  [8] Container status"
    echo "  [Q] Quit"
    echo
}

pause_menu() {
    echo
    read -r -p "  Press Enter to return to menu"
}

invoke_script() {
    local script_name="$1"
    shift || true
    (cd "$SCRIPT_DIR" && bash "./$script_name" "$@")
}

assert_container_running() {
    local state
    state="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)"
    if [[ "$state" != "true" ]]; then
        echo "  Container '$CONTAINER' is not running. Start it first with option [1]."
        return 1
    fi
    return 0
}

select_extensions() {
    local include_examples="${1:-yes}"
    SELECTED_EXTENSIONS=()
    local -a all_paths=()

    mapfile -t user_paths < <(docker exec "$CONTAINER" bash -lc "find '$EXT_USER' -maxdepth 2 \( -name '*.ts' -o -name '*.js' -o -name '*.mjs' \) 2>/dev/null | sort" 2>/dev/null)
    local -a example_paths=()
    if [[ "$include_examples" == "yes" ]]; then
        mapfile -t example_paths < <(docker exec "$CONTAINER" bash -lc "find '$EXT_EXAMPLES' -maxdepth 1 \( -name '*.ts' -o -name '*.js' \) 2>/dev/null | sort" 2>/dev/null)
    fi

    all_paths+=("${user_paths[@]}")
    all_paths+=("${example_paths[@]}")

    local -a filtered=()
    for p in "${all_paths[@]}"; do
        [[ -n "$p" ]] && filtered+=("$p")
    done

    if (( ${#filtered[@]} == 0 )); then
        echo "  No extension files found in the container."
        echo "  User extensions: $EXT_USER"
        if [[ "$include_examples" == "yes" ]]; then
            echo "  Examples:        $EXT_EXAMPLES"
        else
            echo "  (Demo/example extensions were excluded.)"
        fi
        return 1
    fi

    if [[ "$include_examples" == "yes" ]]; then
        echo "  Available extensions (space = example, * = yours):"
    else
        echo "  Available extensions (* = yours):"
    fi
    echo

    local i=1
    local label name dir rel
    for p in "${filtered[@]}"; do
        if [[ "$p" == "$EXT_USER"* ]]; then
            label="*"
        else
            label=" "
        fi
        name="$(basename "$p")"
        dir="$(dirname "$p")"
        rel="${dir/$EXT_EXAMPLES/[examples]}"
        rel="${rel/$EXT_USER/[yours]}"
        printf "  [%2d] %s %s  %s\n" "$i" "$label" "$name" "$rel"
        ((i++))
    done

    echo
    echo "  Enter numbers to load, separated by spaces or commas (e.g. 1 3 5)."
    read -r -p "  Selection (blank to cancel): " raw

    [[ -z "$raw" ]] && return 1

    raw="${raw//,/ }"
    local -a selected=()
    local idx
    for token in $raw; do
        if [[ "$token" =~ ^[0-9]+$ ]]; then
            idx=$((token - 1))
            if (( idx >= 0 && idx < ${#filtered[@]} )); then
                selected+=("${filtered[$idx]}")
            else
                echo "  Skipping invalid index: $token"
            fi
        fi
    done

    (( ${#selected[@]} == 0 )) && return 1

    SELECTED_EXTENSIONS=("${selected[@]}")
    return 0
}

launch_with_extensions() {
    assert_container_running || return 0

    read -r -p "  Include demo/example extensions? (Y/n): " include_examples_raw
    include_examples_raw="${include_examples_raw^^}"
    local include_examples="yes"
    if [[ "$include_examples_raw" == "N" ]]; then
        include_examples="no"
    fi

    select_extensions "$include_examples"
    if (( ${#SELECTED_EXTENSIONS[@]} == 0 )); then
        echo "  No extensions selected. Returning to menu."
        return 0
    fi

    echo
    echo "  Loading extensions:"
    printf '    %s\n' "${SELECTED_EXTENSIONS[@]}"
    echo

    local -a ext_args=()
    local p
    for p in "${SELECTED_EXTENSIONS[@]}"; do
        ext_args+=("--extension" "$p")
    done

    echo "  Launching pi in container..."
    docker exec -it "$CONTAINER" pi "${ext_args[@]}"
}

restore_from_backup_menu() {
    local backup_dir="$SCRIPT_DIR/backups"
    shopt -s nullglob
    local -a files=("$backup_dir"/*.tar.gz)
    shopt -u nullglob

    if (( ${#files[@]} == 0 )); then
        echo "  No backups found in backups/"
        return 0
    fi

    echo "  Available backups:"
    local i=1
    local f
    for f in "${files[@]}"; do
        printf "  [%d] %s\n" "$i" "$(basename "$f")"
        ((i++))
    done

    echo
    read -r -p "  Enter number (or path), blank to cancel: " sel
    [[ -z "$sel" ]] && return 0

    if [[ "$sel" =~ ^[0-9]+$ ]]; then
        local idx=$((sel - 1))
        if (( idx >= 0 && idx < ${#files[@]} )); then
            invoke_script "restore.sh" "${files[$idx]}"
        else
            echo "  Invalid selection."
        fi
    else
        invoke_script "restore.sh" "$sel"
    fi
}

while true; do
    show_menu
    read -r -p "  Select an option: " choice
    choice="${choice^^}"
    echo

    case "$choice" in
        1) invoke_script "launch.sh" ;;
        2) launch_with_extensions ;;
        3) invoke_script "build.sh" ;;
        4) invoke_script "backup.sh" ;;
        5) restore_from_backup_menu ;;
        6) echo "  Stopping pi-agent container..."; docker stop "$CONTAINER" ;;
        7)
            read -r -p "  Remove container pi-agent? Data volume is preserved. (y/N): " confirm
            [[ "${confirm^^}" == "Y" ]] && docker rm -f "$CONTAINER"
            ;;
        8)
            echo "--- docker ps ---"
            docker ps -a --filter "name=$CONTAINER"
            echo
            echo "--- docker volume ---"
            docker volume ls --filter "name=pi-agent-data"
            ;;
        Q) echo "  Bye."; exit 0 ;;
        *) echo "  Unknown option." ;;
    esac

    pause_menu
done


