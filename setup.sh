#!/bin/bash
# Setup wizard for pi-agent configurations

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/configs"
ACTIVE_FILE="$CONFIG_DIR/.active"

# Ensure configs directory exists
mkdir -p "$CONFIG_DIR"

# ── helpers ────────────────────────────────────────────────────────────────────

get_active_profile() {
    if [[ -f "$ACTIVE_FILE" ]]; then
        cat "$ACTIVE_FILE" | tr -d '[:space:]'
    else
        echo ""
    fi
}

get_all_profiles() {
    find "$CONFIG_DIR" -maxdepth 1 -name '*.conf' -print 2>/dev/null | sort | while read -r f; do
        basename "$f" .conf
    done
}

read_profile_value() {
    local file="$1" key="$2"
    grep "^${key}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2-
}

get_docker_status() {
    local container="$1" volume="$2"

    local container_status="not found"
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$container"; then
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$container"; then
            container_status="running"
        else
            container_status="stopped"
        fi
    fi

    local volume_status="not found"
    if docker volume ls --format '{{.Name}}' 2>/dev/null | grep -qx "$volume"; then
        volume_status="exists"
    fi

    echo "$container_status|$volume_status"
}

show_header() {
    clear
    echo
    echo "  pi-agent  --  setup"
    echo "  ==================="
    echo
}

show_profile_list() {
    local active
    active=$(get_active_profile)

    mapfile -t profiles < <(get_all_profiles)

    if (( ${#profiles[@]} == 0 )); then
        echo "  No configurations found."
        echo
        return
    fi

    local i=1
    for name in "${profiles[@]}"; do
        local file="$CONFIG_DIR/${name}.conf"
        local img tag ctn vol
        img=$(read_profile_value "$file" "IMAGE_NAME")
        tag=$(read_profile_value "$file" "IMAGE_TAG")
        ctn=$(read_profile_value "$file" "CONTAINER_NAME")
        vol=$(read_profile_value "$file" "VOLUME_NAME")

        local marker=" "
        [[ "$name" == "$active" ]] && marker="*"

        local status
        status=$(get_docker_status "$ctn" "$vol")
        local c_status="${status%%|*}"

        printf "  [%d] %s %s  %s:%s  %s (%s)\n" "$i" "$marker" "$name" "$img" "$tag" "$ctn" "$c_status"
        ((i++))
    done
    echo
}

# ── wizard: create & build ─────────────────────────────────────────────────────

setup_wizard() {
    # ── Step 1: Profile name ──
    show_header
    echo "  Step 1 — Profile Name"
    echo "  ---------------------"
    echo

    read -r -p "  Name (e.g. default, work, test): " name
    name="$(echo "$name" | xargs)"
    if [[ -z "$name" ]]; then
        echo "  Canceled."
        return
    fi
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "  Invalid name. Use only letters, numbers, dashes, underscores."
        return
    fi

    local conf_file="$CONFIG_DIR/${name}.conf"
    if [[ -f "$conf_file" ]]; then
        echo "  Profile '$name' already exists."
        return
    fi

    # ── Step 2: Docker settings ──
    echo
    echo "  Step 2 — Docker Settings"
    echo "  ------------------------"
    echo "  Press Enter to accept defaults."
    echo

    read -r -p "  Image name     [pi-agent]: " img
    [[ -z "$img" ]] && img="pi-agent"

    read -r -p "  Image tag      [latest]: " tag
    [[ -z "$tag" ]] && tag="latest"

    read -r -p "  Container name [$img]: " ctn
    [[ -z "$ctn" ]] && ctn="$img"

    read -r -p "  Volume name    [${img}-data]: " vol
    [[ -z "$vol" ]] && vol="${img}-data"

    # ── Step 3: Review ──
    echo
    echo "  Step 3 — Review"
    echo "  ---------------"
    echo
    echo "  Profile:   $name"
    echo "  Image:     ${img}:${tag}"
    echo "  Container: $ctn"
    echo "  Volume:    $vol"
    echo

    read -r -p "  Look good? (Y/n): " confirm
    if [[ "${confirm^^}" == "N" ]]; then
        echo "  Canceled."
        return
    fi

    # Save config
    printf "IMAGE_NAME=%s\nIMAGE_TAG=%s\nCONTAINER_NAME=%s\nVOLUME_NAME=%s\n" \
        "$img" "$tag" "$ctn" "$vol" > "$conf_file"
    echo "$name" > "$ACTIVE_FILE"
    echo
    echo "  ✓ Profile '$name' saved and set as active."

    # ── Step 4: Build ──
    echo
    echo "  Step 4 — Build"
    echo "  --------------"
    echo

    read -r -p "  Build the Docker image now? (Y/n): " do_build
    if [[ "${do_build^^}" == "N" ]]; then
        echo
        echo "  Skipped. Run setup again and choose [B] to build later."
        return
    fi

    echo
    build_image

    echo
    echo "  ✓ Setup complete! Run ./run.sh to launch pi."
}

# ── build ──────────────────────────────────────────────────────────────────────

build_image() {
    local active
    active=$(get_active_profile)
    if [[ -z "$active" ]]; then
        echo "  No active profile. Create one first."
        return
    fi

    local build_script="$SCRIPT_DIR/scripts/build.sh"
    if [[ ! -f "$build_script" ]]; then
        echo "  Build script not found: $build_script"
        return
    fi

    echo "  Building image for profile: $active"
    echo

    (cd "$SCRIPT_DIR" && bash "$build_script")
}

# ── edit ───────────────────────────────────────────────────────────────────────

edit_profile() {
    mapfile -t profiles < <(get_all_profiles)
    if (( ${#profiles[@]} == 0 )); then
        echo "  No configurations to edit."
        return
    fi

    show_profile_list

    read -r -p "  Enter number to edit (blank to cancel): " sel
    [[ -z "$sel" ]] && return

    local idx=$((sel - 1))
    if (( idx < 0 || idx >= ${#profiles[@]} )); then
        echo "  Invalid selection."
        return
    fi

    local name="${profiles[$idx]}"
    local file="$CONFIG_DIR/${name}.conf"

    local old_img old_tag old_ctn old_vol
    old_img=$(read_profile_value "$file" "IMAGE_NAME")
    old_tag=$(read_profile_value "$file" "IMAGE_TAG")
    old_ctn=$(read_profile_value "$file" "CONTAINER_NAME")
    old_vol=$(read_profile_value "$file" "VOLUME_NAME")

    echo
    echo "  Editing: $name"
    echo "  Press Enter to keep current value."
    echo

    read -r -p "  Image name     [$old_img]: " img
    [[ -z "$img" ]] && img="$old_img"

    read -r -p "  Image tag      [$old_tag]: " tag
    [[ -z "$tag" ]] && tag="$old_tag"

    read -r -p "  Container name [$old_ctn]: " ctn
    [[ -z "$ctn" ]] && ctn="$old_ctn"

    read -r -p "  Volume name    [$old_vol]: " vol
    [[ -z "$vol" ]] && vol="$old_vol"

    printf "IMAGE_NAME=%s\nIMAGE_TAG=%s\nCONTAINER_NAME=%s\nVOLUME_NAME=%s\n" \
        "$img" "$tag" "$ctn" "$vol" > "$file"

    echo
    echo "  ✓ Profile '$name' updated."

    read -r -p "  Rebuild the Docker image? (y/N): " rebuild
    if [[ "${rebuild^^}" == "Y" ]]; then
        echo "$name" > "$ACTIVE_FILE"
        echo
        build_image
    fi
    echo
}

# ── delete ─────────────────────────────────────────────────────────────────────

delete_profile() {
    mapfile -t profiles < <(get_all_profiles)
    if (( ${#profiles[@]} == 0 )); then
        echo "  No configurations to delete."
        return
    fi

    show_profile_list

    read -r -p "  Enter number to delete (blank to cancel): " sel
    [[ -z "$sel" ]] && return

    local idx=$((sel - 1))
    if (( idx < 0 || idx >= ${#profiles[@]} )); then
        echo "  Invalid selection."
        return
    fi

    local name="${profiles[$idx]}"
    read -r -p "  Delete '$name'? This does NOT remove Docker resources. (y/N): " confirm
    if [[ "${confirm^^}" != "Y" ]]; then
        echo "  Canceled."
        return
    fi

    rm -f "$CONFIG_DIR/${name}.conf"
    echo "  ✓ Profile '$name' deleted."

    local active
    active=$(get_active_profile)
    if [[ "$active" == "$name" ]]; then
        mapfile -t remaining < <(get_all_profiles)
        if (( ${#remaining[@]} > 0 )); then
            echo "${remaining[0]}" > "$ACTIVE_FILE"
            echo "  ✓ Active profile switched to '${remaining[0]}'."
        else
            rm -f "$ACTIVE_FILE"
            echo "  No profiles remaining."
        fi
    fi
    echo
}

# ── main ───────────────────────────────────────────────────────────────────────

mapfile -t _profiles < <(get_all_profiles)

# First run — go straight into wizard
if (( ${#_profiles[@]} == 0 )); then
    show_header
    echo "  No configurations found. Starting setup wizard..."
    echo
    setup_wizard
    read -r -p "  Press Enter to continue"
    mapfile -t _profiles < <(get_all_profiles)
    if (( ${#_profiles[@]} == 0 )); then exit 0; fi
fi

# Management loop
while true; do
    show_header

    local_active=$(get_active_profile)
    show_profile_list

    if [[ -n "$local_active" ]]; then
        echo "  Active: $local_active"
    fi
    echo
    echo "  Enter a number to switch active profile, or:"
    echo
    echo "  [N] New configuration"
    echo "  [E] Edit a configuration"
    echo "  [B] Build / rebuild active image"
    echo "  [D] Delete a configuration"
    echo "  [Q] Done"
    echo

    read -r -p "  Select: " choice
    choice="${choice^^}"
    echo

    # Check if it's a number (switch profile)
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        mapfile -t all_profiles < <(get_all_profiles)
        local_idx=$((choice - 1))
        if (( local_idx >= 0 && local_idx < ${#all_profiles[@]} )); then
            echo "${all_profiles[$local_idx]}" > "$ACTIVE_FILE"
            echo "  ✓ Active profile set to '${all_profiles[$local_idx]}'."
            echo
            read -r -p "  Press Enter to continue"
        else
            echo "  Invalid selection."
            read -r -p "  Press Enter to continue"
        fi
        continue
    fi

    case "$choice" in
        N) setup_wizard; read -r -p "  Press Enter to continue" ;;
        E) edit_profile; read -r -p "  Press Enter to continue" ;;
        B) build_image;  read -r -p "  Press Enter to continue" ;;
        D) delete_profile; read -r -p "  Press Enter to continue" ;;
        Q) echo "  Done."; exit 0 ;;
        *) echo "  Unknown option."; read -r -p "  Press Enter to continue" ;;
    esac
done

