#!/bin/bash
# =============================================================================
# Unified Update Script v4.6 — DFD Compliant Edition
# Purpose: Full automation of llama.cpp update, backup, rollback and system
#          recovery for Pascal (P102-100) and mixed GPU configurations.
# =============================================================================
# <PLAN>
# 1. Configuration block (all constants)
# 2. Logging + helper functions
# 3. GPU detection + smart flag logic
# 4. Service management (stop/start/persist)
# 5. Backup & Restore with history
# 6. Hardware/CUDA/Node.js validation
# 7. Git checkout (latest / date / commit)
# 8. Build with CUDA fixes and deprecated warning suppression
# 9. Main orchestration
#
# Risks mitigated: broken package state, CUDA compiler discovery,
# deprecated GPU targets, service state loss, mixed GPU handling.
# </PLAN>

# [RULE_MANDATORY_COMPLIANCE] + [RULE_STRICTNESS]
set -o nounset
# errexit отключаем глобально, будем проверять возвраты сами
# set -o errexit   # закомментировано
# set -o pipefail  # Commented for maximum compatibility
DEBUG_MODE=true   # или false по умолчанию
while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) DEBUG_MODE=true; shift ;;
        *) shift ;;
    esac
done

# ====================== CONFIGURATION (DFD: RULE_CONFIG_EXEC_SEPARATION) ======================
readonly SCRIPT_VERSION="4.6"
readonly SCRIPT_BASENAME="/opt/llm"
readonly REPO_DIR="${SCRIPT_BASENAME}/llama.cpp"
readonly BACKUP_DIR="${SCRIPT_BASENAME}/backup"
readonly SERVICE_CONFIG="${SCRIPT_BASENAME}/.service_config"
readonly BUILD_HISTORY="${BACKUP_DIR}/build_history.log"

export SERVICE_NAME="${SERVICE_NAME:-llm.service}"

# Hardware requirements
readonly REQUIRED_DRIVER="570.211.01"
readonly REQUIRED_CUDA="12.8"
readonly GPU_NAME_EXPECTED="P102-100"
readonly GPU_MEMORY_EXPECTED="10240"

# State
declare -A SCRIPT_STATE=( [SERVICE_ACTIVE]=false )
GGML_NATIVE="OFF"

# ====================== LOGGING (DFD: RULE_LOG_FORMAT) ======================
log_info()  { echo "[INFO]  $(date '+%H:%M:%S') - $1"; }
log_warn()  { echo "[WARN]  $(date '+%H:%M:%S') - ⚠️  $1"; }
log_error() { echo "[ERR]   $(date '+%H:%M:%S') - ❌ $1"; }
log_success(){ echo "[OK]    $(date '+%H:%M:%S') - ✓ $1"; }
log_step()  { echo "" && echo "=== STEP: $1 ===" && echo ""; }

debug_log() {
    if ${DEBUG_MODE}; then
        echo "[DEBG]  $(date '+%H:%M:%S') - ℹ️  $1"
    fi
}

# ====================== ASCII TABLE HELPER ======================
print_table() {
    local title="$1"
    local -n rows=$2

    local components=()
    local versions=()
    local statuses=()

    local max_comp=0
    local max_ver=0
    local max_stat=0

    # Заголовки
    components+=("Component")
    versions+=("Version")
    statuses+=("Status")

    max_comp=${#components[0]}
    max_ver=${#versions[0]}
    max_stat=${#statuses[0]}

    # Читаем строки
    for row in "${rows[@]}"; do
        IFS='|' read -r comp ver stat <<< "$row"

        components+=("$comp")
        versions+=("$ver")
        statuses+=("$stat")

        [[ ${#comp} -gt $max_comp ]] && max_comp=${#comp}
        [[ ${#ver}  -gt $max_ver  ]] && max_ver=${#ver}
        [[ ${#stat} -gt $max_stat ]] && max_stat=${#stat}
    done

    # +2 для отступов
    local col1_width=$((max_comp + 2))
    local col2_width=$((max_ver + 2))
    local col3_width=$((max_stat + 2))

    # Генератор линии
    local line="+$(printf '%*s' "$col1_width" '' | tr ' ' '-')"
    line+="+$(printf '%*s' "$col2_width" '' | tr ' ' '-')"
    line+="+$(printf '%*s' "$col3_width" '' | tr ' ' '-')+"

    echo ""
    echo "$title"
    echo "$line"

    # Заголовок
    printf "| %-${max_comp}s | %-${max_ver}s | %-${max_stat}s |\n" \
        "${components[0]}" "${versions[0]}" "${statuses[0]}"

    echo "$line"

    # Строки
    for ((i=1; i<${#components[@]}; i++)); do
        local comp="${components[$i]}"
        local ver="${versions[$i]}"
        local stat="${statuses[$i]}"

        local color=""
        local reset=""

        case "$stat" in
            OK)
                color="\033[32m"
                ;;
            WARN)
                color="\033[33m"
                ;;
            FAIL)
                color="\033[31m"
                ;;
        esac

        reset="\033[0m"

        printf "| %-${max_comp}s | %-${max_ver}s | ${color}%-${max_stat}s${reset} |\n" \
            "$comp" "$ver" "$stat"
    done

    echo "$line"
}
# ====================== КОМПЛЕКСНАЯ ПРОВЕРКА (исправлена) ======================
check_all_requirements() {
    local gpu_check_rows=()
    local common_rows=()

    # ----- Расширяем PATH для поиска nvcc (решение проблемы sudo) -----
    local cuda_bin="/usr/local/cuda-${REQUIRED_CUDA}/bin"
    if [[ -d "$cuda_bin" ]] && [[ ":$PATH:" != *":$cuda_bin:"* ]]; then
        export PATH="$cuda_bin:$PATH"
        debug_log "Added $cuda_bin to PATH for CUDA detection"
    fi

    # ----- GPU & Driver detection -----
    local gpu_name=""
    local driver_version=""
    local mem_total=""
    if command -v nvidia-smi >/dev/null 2>&1; then
        driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)
        gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
        mem_total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)
    fi

    # ----- P102‑100 specific checks -----
    local is_pascal=false
    local driver_status="FAIL"
    local cuda_status="FAIL"
    local cuda_display=""

    if [[ "$gpu_name" == *"P102-100"* ]]; then
        is_pascal=true

        # Driver check
        if [[ "$driver_version" == "$REQUIRED_DRIVER" ]]; then
            driver_status="OK"
        elif [[ -n "$driver_version" ]]; then
            driver_status="WARN"
        fi
        gpu_check_rows+=("NVIDIA Driver|${driver_version:-not found}|${driver_status}")

        # CUDA check (теперь PATH уже содержит cuda/bin)
        if command -v nvcc >/dev/null 2>&1; then
            local cuda_version_full=$(nvcc --version | grep "release" | awk '{print $5}' | sed 's/,//')
            if [[ "$cuda_version_full" == *"$REQUIRED_CUDA"* ]]; then
                cuda_status="OK"
                cuda_display="$cuda_version_full"
            else
                cuda_status="WARN"
                cuda_display="$cuda_version_full (expected $REQUIRED_CUDA)"
            fi
        elif [[ -x "$cuda_bin/nvcc" ]]; then
            cuda_status="WARN"
            cuda_display="$REQUIRED_CUDA (installed but not in PATH)"
        else
            cuda_status="FAIL"
            cuda_display="not installed"
        fi
        gpu_check_rows+=("CUDA Toolkit|${cuda_display}|${cuda_status}")
    else
        # Non‑Pascal GPU
        gpu_check_rows+=("GPU Model|${gpu_name:-unknown}|INFO")
        gpu_check_rows+=("Driver|${driver_version:-not found}|INFO")
    fi

    # ----- Common system requirements -----
    local os_version=""
    local os_status="FAIL"
    if grep -q 'VERSION_ID="24.04"' /etc/os-release 2>/dev/null; then
        os_version="Ubuntu 24.04"
        os_status="OK"
    else
        os_version=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Unknown")
        os_status="FAIL"
    fi
    common_rows+=("OS|${os_version}|${os_status}")

    local node_version=$(node --version 2>/dev/null || echo "not installed")
    local npm_version=$(npm --version 2>/dev/null || echo "not installed")
    local node_status="FAIL"
    if command -v npm >/dev/null 2>&1; then
        node_status="OK"
    fi
    common_rows+=("Node.js|${node_version}|${node_status}")
    common_rows+=("npm|${npm_version}|${node_status}")

    local nccl_status="FAIL"
    if ldconfig -p 2>/dev/null | grep -q libnccl; then
        nccl_status="OK"
    fi
    common_rows+=("NCCL (multi-GPU)|${nccl_status}|${nccl_status}")

    # ----- Print tables -----
    if $is_pascal; then
        print_table "=== NVIDIA P102-100 Compatibility Checklist ===" gpu_check_rows
    else
        print_table "=== GPU Information ===" gpu_check_rows
    fi
    print_table "=== System Requirements ===" common_rows

    # ----- Offer automatic fixes for non‑OK items -----
    local need_fix=false
    for row in "${gpu_check_rows[@]}" "${common_rows[@]}"; do
        if [[ "$row" == *"|WARN"* || "$row" == *"|FAIL"* ]]; then
            need_fix=true
            break
        fi
    done

    if $need_fix; then
        echo ""
        read -p "Some checks failed. Apply automatic fixes? [Y/n] " fix_choice
        if [[ ! "$fix_choice" =~ ^[Nn]$ ]]; then
            if [[ "$driver_status" != "OK" ]] && [[ "$gpu_name" == *"P102-100"* ]]; then
                ensure_nvidia_driver
            fi
            if [[ "$cuda_status" != "OK" ]]; then
                ensure_cuda_installed
            fi
            if [[ "$node_status" != "OK" ]]; then
                ensure_nodejs
            fi
            if [[ "$nccl_status" != "OK" ]]; then
                ensure_nccl
            fi
            echo ""
            log_info "Fixes applied. Please re-run the script to verify."
            exit 0
        fi
    fi
}

ensure_cuda_installed() {
    log_info "Checking CUDA installation..."

    # Ищем nvcc в PATH и в стандартных местах
    local nvcc_path=""
    if command -v nvcc >/dev/null 2>&1; then
        nvcc_path=$(command -v nvcc)
    elif [[ -x "/usr/local/cuda-${REQUIRED_CUDA}/bin/nvcc" ]]; then
        nvcc_path="/usr/local/cuda-${REQUIRED_CUDA}/bin/nvcc"
    fi

    if [[ -n "$nvcc_path" ]]; then
        local cuda_version=$("$nvcc_path" --version | grep "release" | awk '{print $5}' | sed 's/,//')
        log_info "Found CUDA ${cuda_version} at $nvcc_path"

        if [[ "$cuda_version" == *"${REQUIRED_CUDA}"* ]]; then
            log_success "Correct CUDA version (${REQUIRED_CUDA}) already installed"
            return 0
        else
            log_warn "Found CUDA ${cuda_version}, but ${REQUIRED_CUDA} is required"
        fi
    else
        log_warn "nvcc not found → CUDA Toolkit not installed"
    fi

    # Интерактивная установка только если запущено из терминала
    if [[ -t 0 ]]; then
        read -p "Install/Repair CUDA ${REQUIRED_CUDA}? [Y/n] " choice
        if [[ "$choice" =~ ^[Nn]$ ]]; then
            log_warn "Continuing without proper CUDA. Build may fail."
            return 1
        fi
    else
        log_info "Non-interactive mode: installing CUDA ${REQUIRED_CUDA} automatically"
    fi

    log_info "Installing CUDA ${REQUIRED_CUDA}..."
    local keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb"

    wget -q "${keyring_url}" -O /tmp/cuda-keyring.deb
    sudo dpkg -i /tmp/cuda-keyring.deb
    rm -f /tmp/cuda-keyring.deb

    sudo apt-get update -qq
    sudo apt-get install -y cuda-toolkit-12-8

    # Добавляем /usr/local/cuda-12.8/bin в PATH для текущей сессии
    export PATH="/usr/local/cuda-${REQUIRED_CUDA}/bin:$PATH"

    if command -v nvcc >/dev/null 2>&1; then
        log_success "CUDA ${REQUIRED_CUDA} installed successfully"
    else
        log_error "CUDA installation failed"
        return 1
    fi
}
# ====================== GPU DETECTION ======================
detect_gpus() {
    log_info "Detecting NVIDIA GPUs..."

    # Временно отключаем errexit для безопасного опроса nvidia-smi
    set +e
    local smi_output
    smi_output=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader,nounits 2>/dev/null)
    local smi_exit=$?
    set -e

    if [[ $smi_exit -ne 0 || -z "$smi_output" ]]; then
        log_warn "nvidia-smi failed or no GPUs found. Falling back to CUDA_ARCH=61"
        export CMAKE_CUDA_ARCHITECTURES="61"
        GGML_NATIVE="OFF"

    fi

    local arch_list=""
    local has_pascal=false
    local gpu_count=0

    while IFS= read -r cc_raw; do
        [[ -z "$cc_raw" ]] && continue
        local cc=$(echo "$cc_raw" | tr -d '.')
        ((gpu_count++))
        [[ -z "$arch_list" ]] && arch_list="$cc" || arch_list="${arch_list};${cc}"
        [[ "$cc" == "61" ]] && has_pascal=true
        debug_log "GPU ${gpu_count}: Compute Capability ${cc_raw} → ${cc}"
    done <<< "$smi_output"

    export CMAKE_CUDA_ARCHITECTURES="${arch_list:-61}"
    log_success "Detected ${gpu_count} GPU(s). Architectures: ${CMAKE_CUDA_ARCHITECTURES}"

    if $has_pascal; then
        GGML_NATIVE="OFF"
        log_warn "Pascal detected → GGML_NATIVE=OFF"
    else
        GGML_NATIVE="ON"
    fi
}

# ====================== NODEJS & NPM ======================
ensure_nodejs() {
    if command -v npm >/dev/null 2>&1; then
        log_success "npm already installed ($(npm --version))"
        return 0
    fi

    log_warn "npm not found. WebUI requires it for optimal experience."
    read -p "Install Node.js (recommended)? [Y/n] " choice
    if [[ "$choice" =~ ^[Nn]$ ]]; then
        log_warn "Continuing without npm. Will use pre-built WebUI."
        return 1
    fi

    log_info "Installing Node.js via NodeSource (LTS)..."

    # Сначала пробуем обычную установку
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    if sudo apt-get install -y nodejs; then
        log_success "Node.js installed successfully ($(node --version) / $(npm --version))"
        return 0
    fi

    # Если не получилось — предлагаем агрессивную очистку
    log_warn "Standard installation failed. Try aggressive cleanup?"
    read -p "Perform cleanup and retry? [y/N] " cleanup_choice

    if [[ "$cleanup_choice" =~ ^[Yy]$ ]]; then
        log_info "Performing cleanup of conflicting packages..."
        sudo apt-get remove -y nodejs npm libnode* 2>/dev/null || true
        sudo apt-get purge -y nodejs npm libnode* 2>/dev/null || true
        sudo apt-get autoremove -y --purge 2>/dev/null || true

        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi

    if command -v npm >/dev/null 2>&1; then
        log_success "Node.js installed after cleanup ($(node --version) / $(npm --version))"
    else
        log_error "Failed to install Node.js. You can install it manually later."
    fi
}

# ====================== SERVICE MANAGEMENT ======================
load_service_config() {
    if [ -f "$SERVICE_CONFIG" ]; then
        source "$SERVICE_CONFIG"
        export SERVICE_NAME
        log_info "Loaded service config: $SERVICE_NAME"
    else
        log_warn "No service config found. Using default: llm.service"
    fi
}

save_service_config() {
    echo "export SERVICE_NAME=\"${1}\"" > "$SERVICE_CONFIG"
    log_success "Service name saved: $1"
}

check_initial_service_status() {
    if systemctl list-unit-files --type=service | grep -q "^${SERVICE_NAME}"; then
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            SCRIPT_STATE["SERVICE_ACTIVE"]=true
            log_info "Service ${SERVICE_NAME} is currently ACTIVE"
        fi
        save_service_config "$SERVICE_NAME"   # Автосохранение
    else
        log_warn "Service unit '${SERVICE_NAME}' not found in systemd"
    fi
}

stop_service() {
    if ${SCRIPT_STATE["SERVICE_ACTIVE"]}; then
        log_info "Stopping service ${SERVICE_NAME}..."
        sudo systemctl stop "$SERVICE_NAME" || true
    fi
}

start_service() {
    if ${SCRIPT_STATE["SERVICE_ACTIVE"]}; then
        log_info "Starting service ${SERVICE_NAME}..."
        sudo systemctl start "$SERVICE_NAME"
        sleep 3
        systemctl is-active --quiet "$SERVICE_NAME" && log_success "Service started" || log_warn "Failed to start service"
    fi
}

# ====================== BUILD HISTORY ======================
save_build_log() {
    mkdir -p "${BACKUP_DIR}"
    local commit=$(cd "${REPO_DIR}" 2>/dev/null && git rev-parse --short HEAD 2>/dev/null || echo "unknown")

    {
        echo "=== Build $(date '+%Y-%m-%d %H:%M:%S') ==="
        echo "Commit: $commit"
        echo "CUDA Architectures: ${CMAKE_CUDA_ARCHITECTURES}"
        echo "GGML_NATIVE: ${GGML_NATIVE}"
        echo "CUDA: ${REQUIRED_CUDA}"
        echo "Driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 2>/dev/null || echo 'unknown')"
        echo "----------------------------------------"
    } >> "${BUILD_HISTORY}"
    log_info "Build record saved to ${BUILD_HISTORY}"
}

# ====================== BACKUP & RESTORE ======================
create_backup() {
    mkdir -p "${BACKUP_DIR}"
    local backup_name="backup_$(date '+%Y%m%d_%H%M%S')"
    local backup_path="${BACKUP_DIR}/${backup_name}"

    log_info "Creating backup → ${backup_path}"
    cp -ra "${REPO_DIR}" "${backup_path}" || { log_error "Backup failed"; return 1; }

    # Keep only last 10 backups
    find "${BACKUP_DIR}" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | \
        sort -rn | tail -n +11 | cut -d' ' -f2- | xargs -r rm -rf

    log_success "Backup created: ${backup_name}"
}

list_backups() {
    echo ""
    echo "Available backups:"
    echo "----------------------------------------"
    printf "%-3s %-30s %-15s\n" "ID" "Name" "Size"
    echo "----------------------------------------"
    local count=0
    while IFS= read -r dir; do
        ((count++))
        local name=$(basename "$dir")
        local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        printf "%-3s %-30s %-15s\n" "$count" "$name" "$size"
    done < <(find "${BACKUP_DIR}" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -rn)
    [[ $count -gt 0 ]]
}

restore_backup_interactive() {
    if ! list_backups; then return 1; fi

    read -p "Select backup ID to restore (1-10): " selected_id
    local target_backup=""
    local count=0

    while IFS= read -r dir; do
        ((count++))
        if [[ $count -eq $selected_id ]]; then
            target_backup="$dir"
            break
        fi
    done < <(find "${BACKUP_DIR}" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -rn)

    if [ -z "$target_backup" ]; then
        log_error "Invalid backup ID"
        return 1
    fi

    read -p "Restore $(basename "$target_backup")? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || return 0

    rm -rf "${REPO_DIR}"
    cp -ra "$target_backup" "${REPO_DIR}"
    log_success "Successfully restored from $(basename "$target_backup")"
}

# ====================== GIT ======================
git_checkout_target() {
    local target="${1:-latest}"
    cd "${REPO_DIR}" || { log_error "Cannot cd to repo"; return 1; }

    if [[ "$target" == "latest" ]]; then
        log_info "Pulling latest version..."
        git fetch --all --prune
        git reset --hard origin/master 2>/dev/null || git reset --hard origin/main
        git pull origin master 2>/dev/null || git pull origin main
        log_success "Latest master/main checked out"
    elif [[ "$target" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        log_info "Rolling back to date: $target"
        git fetch --all
        local commit=$(git rev-list -n 1 --before="$target 23:59:59" origin/master 2>/dev/null || \
                       git rev-list -n 1 --before="$target 23:59:59" origin/main)
        if [ -z "$commit" ]; then
            log_error "No commit found for date $target"
            return 1
        fi
        git reset --hard "$commit"
        log_success "Rolled back to commit from $(git show -s --format=%cd --date=short "$commit")"
    else
        log_info "Checking out commit: $target"
        git reset --hard "$target"
    fi
}

# ====================== DRIVER INSTALLATION ======================
ensure_nvidia_driver() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        log_success "NVIDIA driver already installed"
        return 0
    fi

    log_warn "NVIDIA driver not found"
    read -p "Automatically install NVIDIA driver ${REQUIRED_DRIVER}? [Y/n] " choice
    if [[ "$choice" =~ ^[Nn]$ ]]; then
        log_error "Driver required for GPU operation. Exiting."
        exit 1
    fi

    log_info "Installing NVIDIA driver ${REQUIRED_DRIVER}..."
    sudo apt-get update -qq

    # Добавляем официальный репозиторий NVIDIA
    local keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb"
    wget -q "${keyring_url}" -O /tmp/cuda-keyring.deb
    sudo dpkg -i /tmp/cuda-keyring.deb
    rm -f /tmp/cuda-keyring.deb
    sudo apt-get update -qq

    # Устанавливаем драйвер (версия 570 из репозитория)
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        nvidia-driver-570 \
        nvidia-utils-570 \
        nvidia-firmware-570-570.211.01

    log_info "Driver installation completed. A reboot is required."
    read -p "Reboot now? [y/N] " reboot_choice
    if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
        sudo reboot
    else
        log_warn "Please reboot manually before continuing."
        exit 0
    fi
}

# ====================== HARDWARE VALIDATION ======================
validate_os() {
    if ! grep -q 'VERSION_ID="24.04"' /etc/os-release; then
        log_error "Ubuntu 24.04 required"
        return 1
    fi
    log_success "OS: Ubuntu 24.04 confirmed"
}

validate_hardware() {
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        ensure_nvidia_driver
        # После установки драйвера скрипт либо ребутнулся, либо вышел.
        # Сюда не дойдём, но на всякий случай:
        return 1
    fi

    local driver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)
    local gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
    local mem=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)

    log_info "Driver: ${driver} | GPU: ${gpu_name} | Memory: ${mem}MB"

    if [[ "$driver" != "$REQUIRED_DRIVER" ]]; then
        log_warn "Driver version mismatch! Expected: ${REQUIRED_DRIVER}, found: ${driver}"
        log_warn "Consider upgrading: sudo apt install nvidia-driver-${REQUIRED_DRIVER%%*}"
    fi

    if [[ ! "$gpu_name" =~ $GPU_NAME_EXPECTED ]]; then
        log_warn "GPU mismatch. Expected ${GPU_NAME_EXPECTED}, found ${gpu_name}"
        read -p "Continue anyway? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || return 1
    fi
}

ensure_nccl() {
    if ldconfig -p 2>/dev/null | grep -q libnccl; then
        debug_log "NCCL already installed"
        return 0
    fi
    log_warn "Installing NCCL (for multi-GPU)..."
    sudo apt-get update -qq
    sudo apt-get install -y libnccl2 libnccl-dev
    log_success "NCCL installed"
}

# ====================== BUILD ======================
perform_build() {
    cd "${REPO_DIR}" || return 1
    local build_dir="${REPO_DIR}/build"
    local cuda_path="/usr/local/cuda-${REQUIRED_CUDA}"
    local nvcc_path="${cuda_path}/bin/nvcc"

 
    # === КРИТИЧНЫЕ ПАРАМЕТРЫ ДЛЯ CUDA ===
    if [ ! -x "$nvcc_path" ]; then
        log_error "nvcc not found at $nvcc_path"
        log_error "Please check CUDA installation"
        return 1
    fi

   rm -rf "$build_dir" && mkdir -p "$build_dir"

    log_info "Using nvcc: $nvcc_path"
    log_info "Building with architectures: ${CMAKE_CUDA_ARCHITECTURES}"

    cmake -S . -B "$build_dir" \
        -DCMAKE_CUDA_COMPILER="${nvcc_path}" \
        -DCMAKE_CUDA_ARCHITECTURES="${CMAKE_CUDA_ARCHITECTURES}" \
        -DGGML_CUDA=ON \
        -DGGML_CURL=ON \
        -DGGML_CUDA_FA_ALL_QUANTS=ON \
        -DGGML_NATIVE=${GGML_NATIVE} \
        -DCMAKE_CUDA_FLAGS="-Wno-deprecated-gpu-targets" \
        -DCMAKE_BUILD_TYPE=Release \
        || { log_error "CMake failed"; return 1; }

    log_info "Starting compilation..."
    cmake --build "$build_dir" --config Release -j$(nproc) \
        --target llama-cli llama-server llama-gguf-split \
        || { log_error "Build failed"; return 1; }

    log_success "Build completed successfully"
}

deploy_binaries() {
    cp -f "${REPO_DIR}/build/bin/llama-"* "${SCRIPT_BASENAME}/" 2>/dev/null || true
    log_success "Binaries deployed to ${SCRIPT_BASENAME}"
}

# ====================== MAIN ENTRY POINT ======================
main() {
    echo "=================================================="
    echo "    LLM Update Script v${SCRIPT_VERSION} — DFD Compliant"
    echo "    Repo: ${REPO_DIR}"
    echo "=================================================="

    load_service_config

   check_all_requirements

    #. GPU detection (полагается на работающий nvidia-smi и CUDA)
    detect_gpus || {
        log_warn "GPU detection failed, using safe defaults (CUDA_ARCH=61)"
        export CMAKE_CUDA_ARCHITECTURES="61"
        GGML_NATIVE="OFF"
    }

    check_initial_service_status

    echo ""
    echo "Select action:"
    echo "  [1] Update / Build"
    echo "  [2] Rollback to previous build"
    echo "  [3] Exit"
    read -p "Selection: " action

    case "$action" in
        1)
            log_step "Updating llama.cpp"
            stop_service
            create_backup

            validate_os
            validate_hardware
            ensure_nccl
            ensure_nodejs

            echo ""
            echo "Select version to build:"
            echo "  [1] Latest (master)"
            echo "  [2] By date (YYYY-MM-DD)"
            echo "  [3] By commit"
            read -p "Choice [1]: " git_choice
            git_choice=${git_choice:-1}

            local git_target="latest"
            if [[ "$git_choice" == "2" ]]; then
                read -p "Enter date (YYYY-MM-DD): " git_target
            elif [[ "$git_choice" == "3" ]]; then
                read -p "Enter commit hash: " git_target
            fi

            git_checkout_target "$git_target"
            perform_build
            deploy_binaries
            save_build_log
            start_service
            ;;

        2)
            log_step "Rollback to previous build"
            restore_backup_interactive
            start_service
            ;;

        3)
            log_info "Exiting without changes"
            exit 0
            ;;

        *)
            log_error "Invalid selection"
            exit 1
            ;;
    esac

    log_success "Operation completed successfully"
}

main "$@"
