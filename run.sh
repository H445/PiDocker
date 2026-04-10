#!/bin/bash
# Interactive menu to manage the pi-agent container

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER="pi-agent"
EXT_EXAMPLES="/usr/local/lib/node_modules/@mariozechner/pi-coding-agent/examples/extensions"
EXT_USER="/root/.pi/extensions"
SELECTED_EXTENSIONS=()

# ── helpers ────────────────────────────────────────────────────────────────────

show_menu() {
    clear
    echo
    echo "  pi-agent  --  management menu"
    echo "  ================================"
    echo
    echo "  [1] Launch pi                (launch.sh)"
    echo "  [2] Launch pi with extensions"
    echo "  [3] Open container shell"
    echo "  [4] Build image              (build.sh)"
    echo "  [5] Provider configuration   (localprovider.sh)"
    echo "  [6] Backup management"
    echo "  [7] Container management"
    echo "  [Q] Quit"
    echo
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

# ── open container shell ───────────────────────────────────────────────────────

open_container_shell() {
    assert_container_running || return 0

    echo
    echo "  Opening bash shell in container (type 'exit' to return to menu)..."
    echo
    docker exec -it "$CONTAINER" bash
}

# ── backup management ──────────────────────────────────────────────────────────

get_backup_files() {
    local backup_dir="$SCRIPT_DIR/backups"
    [[ -d "$backup_dir" ]] || return 0
    find "$backup_dir" -maxdepth 1 -type f -name '*.tar.gz' -print 2>/dev/null | sort -r
}

show_backup_list() {
    mapfile -t files < <(get_backup_files)
    if (( ${#files[@]} == 0 )); then
        echo "  No backups found in backups/"
        return 1
    fi

    echo "  Available backups:"
    local i=1
    local f bytes size_kb modified
    for f in "${files[@]}"; do
        bytes="$(stat -c %s "$f" 2>/dev/null || echo 0)"
        size_kb=$(awk "BEGIN {printf \"%.1f\", $bytes / 1024}")
        modified=$(date -r "$f" "+%Y-%m-%d %H:%M" 2>/dev/null \
                || stat -c %y "$f" 2>/dev/null | cut -d'.' -f1)
        printf "  [%d] %s  (%s KB, %s)\n" "$i" "$(basename "$f")" "$size_kb" "$modified"
        ((i++))
    done
    return 0
}

restore_backup_menu() {
    show_backup_list || return 0

    echo
    read -r -p "  Enter number (or path), blank to cancel: " sel
    [[ -z "$sel" ]] && return 0

    mapfile -t files < <(get_backup_files)
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

delete_backup_menu() {
    show_backup_list || return 0

    echo
    read -r -p "  Enter number (or path) to delete, blank to cancel: " sel
    [[ -z "$sel" ]] && return 0

    local target=""
    mapfile -t files < <(get_backup_files)
    if [[ "$sel" =~ ^[0-9]+$ ]]; then
        local idx=$((sel - 1))
        if (( idx >= 0 && idx < ${#files[@]} )); then
            target="${files[$idx]}"
        else
            echo "  Invalid selection."
            return 0
        fi
    else
        target="$sel"
    fi

    if [[ ! -f "$target" ]]; then
        echo "  Backup not found: $target"
        return 0
    fi

    local name
    name="$(basename "$target")"
    read -r -p "  Delete '$name'? (y/N): " confirm
    if [[ "${confirm^^}" != "Y" ]]; then
        echo "  Delete canceled."
        return 0
    fi

    rm -f -- "$target"
    echo "  Backup deleted."
}

show_backup_menu() {
    echo
    echo "  Backup Management"
    echo "  ================="
    echo
    echo "  [1] Create backup  (backup.sh)"
    echo "  [2] List backups"
    echo "  [3] Restore backup (restore.sh)"
    echo "  [4] Delete backup"
    echo
    echo "  Press Enter to go back."
    echo
}

backup_management_menu() {
    while true; do
        show_backup_menu
        read -r -p "  Select an option: " choice
        [[ -z "$choice" ]] && return 0
        choice="${choice^^}"
        echo

        case "$choice" in
            1) invoke_script "backup.sh" ;;
            2) show_backup_list ;;
            3) restore_backup_menu ;;
            4) delete_backup_menu ;;
            *) echo "  Unknown option." ;;
        esac

        echo
        read -r -p "  Press Enter to continue"
    done
}

# ── container management ───────────────────────────────────────────────────────

show_container_menu() {
    echo
    echo "  Container Management"
    echo "  ===================="
    echo
    echo "  [1] Stop container"
    echo "  [2] Remove container (keep volume)"
    echo "  [3] Container status"
    echo
    echo "  Press Enter to go back."
    echo
}

container_management_menu() {
    while true; do
        show_container_menu
        read -r -p "  Select an option: " choice
        [[ -z "$choice" ]] && return 0
        choice="${choice^^}"
        echo

        case "$choice" in
            1)
                echo "  Stopping pi-agent container..."
                docker stop "$CONTAINER"
                ;;
            2)
                read -r -p "  Remove container? Data volume is preserved. (y/N): " confirm
                [[ "${confirm^^}" == "Y" ]] && docker rm -f "$CONTAINER"
                ;;
            3)
                echo "--- docker ps ---"
                docker ps -a --filter "name=$CONTAINER"
                echo
                echo "--- docker volume ---"
                docker volume ls --filter "name=pi-agent-data"
                ;;
            *) echo "  Unknown option." ;;
        esac

        echo
        read -r -p "  Press Enter to continue"
    done
}

# ── extension picker ───────────────────────────────────────────────────────────

select_extensions() {
    local include_examples="${1:-yes}"
    SELECTED_EXTENSIONS=()
    local -a all_paths=()

    mapfile -t user_paths < <(docker exec "$CONTAINER" bash -lc \
        "find '$EXT_USER' -maxdepth 2 \( -name '*.ts' -o -name '*.js' -o -name '*.mjs' \) 2>/dev/null | sort" 2>/dev/null)

    local -a example_paths=()
    if [[ "$include_examples" == "yes" ]]; then
        mapfile -t example_paths < <(docker exec "$CONTAINER" bash -lc \
            "find '$EXT_EXAMPLES' -maxdepth 1 \( -name '*.ts' -o -name '*.js' \) 2>/dev/null | sort" 2>/dev/null)
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

# ── launch with extensions ─────────────────────────────────────────────────────

launch_with_extensions() {
    assert_container_running || return 0

    read -r -p "  Include demo/example extensions? (Y/n): " include_examples_raw
    include_examples_raw="${include_examples_raw^^}"
    local include_examples="yes"
    [[ "$include_examples_raw" == "N" ]] && include_examples="no"

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

# ── main loop ──────────────────────────────────────────────────────────────────

while true; do
    show_menu
    read -r -p "  Select an option: " choice
    choice="${choice^^}"
    echo

    case "$choice" in
        1) invoke_script "launch.sh" ;;
        2) launch_with_extensions ;;
        3) open_container_shell ;;
        4) invoke_script "build.sh" ;;
        5) invoke_script "localprovider.sh" ;;
        6) backup_management_menu ;;
        7) container_management_menu ;;
        Q) echo "  Bye."; exit 0 ;;
        *) echo "  Unknown option." ;;
    esac

    # Pause after output-producing actions so results aren't erased by clear.
    # Submenus (6, 7) handle their own flow — no extra pause needed.
    case "$choice" in
        6|7|Q) ;;
        *) echo; read -r -p "  Press Enter to return to menu" ;;
    esac
done
