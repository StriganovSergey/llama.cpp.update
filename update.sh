#!/bin/bash
# =============================================================================
# Unified Update Script v6.2 — DFD Compliant Edition (Clean Build Log)
# Purpose: Full automation of llama.cpp update, backup, rollback and system
#          recovery for Pascal (P102-100) and mixed GPU configurations.
#          FIXES: Lock file, build tools check, detailed deployment diagnostics,
#                 retry option instead of forced rollback, --until for date selection,
#                 full compilation flags logging, auto-deploy on rollback,
#                 FIXED backup restore path parsing, CLEAN BUILD LOG FORMAT,
#                 SYMLINK-AWARE DEPLOYMENT (idempotent copy skip),
#                 VERSION BUMP & COMMIT-AWARE BACKUP NAMING WITH DUPLICATE CHECK,
#                 UNIQUE GPU ARCHITECTURE DEDUPLICATION,
#                 CPU-BASED GGML_NATIVE STRATEGY (independent of GPU age),
#                 BACKUP NAME INCLUDES COMMIT DATE,
#                 MULTI-ARCH BUILD OPTION,
#                 CMAKE_EXTRA_FLAGS ACTUALLY USED,
#                 FULL GPU LIST IN BUILD LOG,
#                 MULTI-ARCH SUMMARY WITH COPY COMMANDS,
#                 ALREADY UP-TO-DATE CHECK.
# =============================================================================
# <PLAN>
# 1. Configuration block (all constants)
# 2. Logging + helper functions
# 3. Lock file mechanism (prevent concurrent runs)
# 4. Build tools check and auto-install
# 5. GPU detection + smart flag logic (deduplicated architectures)
# 6. Build strategy decision based on CPU capabilities (AVX2/AVX512)
# 7. Service management (stop/start/persist/status)
# 8. Backup & Restore with history, commit-aware naming & duplicate prompt
# 9. Hardware/CUDA/Node.js validation
# 10. Git checkout (latest / date / commit)
# 11. Build with CUDA fixes, strategy handling, and deprecated warning suppression
# 12. Deployment with symlink detection, idempotent copy skip, and diagnostics
# 13. Main orchestration with strict error handling
#
# Risks mitigated: concurrent execution, missing tools, deployment failures,
# unclear error messages, forced rollback without retry, incomplete build logs,
# missing deployment after rollback, broken backup restore path parsing,
# symlink copy conflicts (cp "same file" error), duplicate backups for same commit,
# redundant GPU architecture flags, suboptimal CPU instruction selection.
# </PLAN>

# [RULE_MANDATORY_COMPLIANCE] + [RULE_STRICTNESS]
set -o nounset
DEBUG_MODE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) DEBUG_MODE=true; shift ;;
        *) shift ;;
    esac
done

# ====================== CONFIGURATION (DFD: RULE_CONFIG_EXEC_SEPARATION) ======================
readonly SCRIPT_VERSION="6.2"
readonly SCRIPT_BASENAME="/opt/llm"
readonly REPO_DIR="${SCRIPT_BASENAME}/llama.cpp"
readonly BACKUP_DIR="${SCRIPT_BASENAME}/backup"
readonly SERVICE_CONFIG="${SCRIPT_BASENAME}/.service_config"
readonly BUILD_HISTORY="${BACKUP_DIR}/build_history.log"
readonly LOCK_FILE="/var/run/llm-update.lock"

export SERVICE_NAME="${SERVICE_NAME:-llm.service}"

# Hardware requirements
readonly REQUIRED_DRIVER="570.211.01"
readonly REQUIRED_CUDA="12.8"
readonly GPU_NAME_EXPECTED="P102-100"
readonly GPU_MEMORY_EXPECTED="10240"

# State
declare -A SCRIPT_STATE=( [SERVICE_ACTIVE]=false )
GGML_NATIVE="OFF"
BUILD_MULTIARCH_MODE="OFF"  # for multi-arch decision

# Track last backup for automatic rollback on failure
LAST_BACKUP_PATH=""

# Track deployment error details for diagnostics
DEPLOY_ERROR_REASON=""
DEPLOY_ERROR_DETAILS=""

# Track build details for logging
BUILD_TIMESTAMP=""
BUILD_COMMIT=""
BUILD_COMMIT_DATE=""
BUILD_CMAKE_ARGS=""
BUILD_MAKE_ARGS=""

# Track if service was stopped (for auto-restart on rollback)
SERVICE_WAS_STOPPED=false

# ====================== LOCK FILE MANAGEMENT ======================
acquire_lock() {
    # Ensure lock directory exists
    local lock_dir=$(dirname "$LOCK_FILE")
    if [ ! -d "$lock_dir" ]; then
        sudo mkdir -p "$lock_dir" 2>/dev/null || {
            log_error "Cannot create lock directory: $lock_dir"
            log_error "Please run: sudo mkdir -p $lock_dir"
            return 1
        }
    fi

    # Create lock file with exclusive lock
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        log_error "Another instance of this script is already running"
        log_error "Lock file: $LOCK_FILE"
        log_error "To force release (if script crashed): sudo rm $LOCK_FILE"
        log_error "Or wait for the other instance to finish"
        exit 1
    fi
    debug_log "Lock acquired successfully"
    return 0
}

release_lock() {
    flock -u 200 2>/dev/null || true
    rm -f "$LOCK_FILE" 2>/dev/null || true
    debug_log "Lock released"
}

# Trap to release lock on exit
trap release_lock EXIT

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

# ====================== BUILD TOOLS CHECK & AUTO-INSTALL ======================
check_build_tools() {
    local missing_tools=()
    local install_commands=()

    log_info "Checking build tools..."

    # Check git
    if ! command -v git >/dev/null 2>&1; then
        missing_tools+=("git")
        install_commands+=("sudo apt-get install -y git")
    else
        debug_log "git: $(git --version)"
    fi

    # Check cmake
    if ! command -v cmake >/dev/null 2>&1; then
        missing_tools+=("cmake")
        install_commands+=("sudo apt-get install -y cmake")
    else
        debug_log "cmake: $(cmake --version | head -n1)"
    fi

    # Check make
    if ! command -v make >/dev/null 2>&1; then
        missing_tools+=("make")
        install_commands+=("sudo apt-get install -y make")
    else
        debug_log "make: $(make --version | head -n1)"
    fi

    # Check gcc/g++
    if ! command -v gcc >/dev/null 2>&1; then
        missing_tools+=("gcc")
        install_commands+=("sudo apt-get install -y build-essential")
    else
        debug_log "gcc: $(gcc --version | head -n1)"
    fi

    # Check nproc (for parallel builds)
    if ! command -v nproc >/dev/null 2>&1; then
        missing_tools+=("nproc")
        install_commands+=("sudo apt-get install -y procps")
    fi

    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        log_success "All build tools are installed"
        return 0
    fi

    log_warn "Missing build tools: ${missing_tools[*]}"
    echo ""
    echo "Missing tools detected. Install options:"
    echo "  [1] Install all missing tools automatically"
    echo "  [2] Skip and continue (build may fail)"
    echo "  [3] Exit script"
    read -p "Choice [1]: " tool_choice
    tool_choice=${tool_choice:-1}

    case "$tool_choice" in
        1)
            log_info "Installing missing tools..."
            for cmd in "${install_commands[@]}"; do
                log_info "Running: $cmd"
                if ! eval "$cmd"; then
                    log_error "Failed to install: $cmd"
                    return 1
                fi
            done
            log_success "All tools installed"
            return 0
            ;;
        2)
            log_warn "Continuing without all build tools. Build may fail."
            return 0
            ;;
        3)
            log_info "Exiting script"
            exit 0
            ;;
        *)
            log_error "Invalid choice"
            return 1
            ;;
    esac
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
    local critical_fail=false

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

    # ----- P102 100 specific checks -----
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
        # Non Pascal GPU
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
        else
            critical_fail=true
        fi
    fi

    if $critical_fail; then
        log_error "Critical requirements not met and fixes declined."
        return 1
    fi
    return 0
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

    log_info "Downloading CUDA keyring..."
    if ! wget "${keyring_url}" -O /tmp/cuda-keyring.deb; then
        log_error "Download failed"
        return 1
    fi

    log_info "Installing CUDA keyring (GPG verification handled by apt)..."
    sudo dpkg -i /tmp/cuda-keyring.deb
    rm -f /tmp/cuda-keyring.deb

    sudo apt-get update -qq
    sudo apt-get install -y cuda-toolkit-12-8

    # Добавляем /usr/local/cuda-12.8/bin в PATH для текущей сессии
    export PATH="/usr/local/cuda-${REQUIRED_CUDA}/bin:$PATH"

    if command -v nvcc >/dev/null 2>&1; then
        log_success "CUDA ${REQUIRED_CUDA} installed successfully"
        return 0
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
        return 1
    fi

    local arch_list=""
    local has_pascal=false
    local gpu_count=0
    local gpu_names=() # Store all unique GPU names

    while IFS= read -r cc_raw; do
        [[ -z "$cc_raw" ]] && continue
        local cc=$(echo "$cc_raw" | tr -d '.')
        ((gpu_count++))
        
        # Deduplicate architectures: only add if not already present
        if [[ ";${arch_list};" != *";${cc};"* ]]; then
            [[ -z "$arch_list" ]] && arch_list="$cc" || arch_list="${arch_list};${cc}"
        fi
        
        [[ "$cc" == "61" ]] && has_pascal=true
        debug_log "GPU ${gpu_count}: Compute Capability ${cc_raw} → ${cc}"
    done <<< "$smi_output"

    # Get unique GPU names for logging
    if command -v nvidia-smi >/dev/null 2>&1; then
        local names_output=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null)
        while IFS= read -r name; do
            [[ -z "$name" ]] && continue
            # Add to list if not already present (simple check)
            local found=false
            for existing in "${gpu_names[@]}"; do
                if [[ "$existing" == "$name" ]]; then
                    found=true
                    break
                fi
            done
            if ! $found; then
                gpu_names+=("$name")
            fi
        done <<< "$names_output"
    fi

    export CMAKE_CUDA_ARCHITECTURES="${arch_list:-61}"
    log_success "Detected ${gpu_count} GPU(s). Unique Architectures: ${CMAKE_CUDA_ARCHITECTURES}"

    # Store names for later use in history
    export DETECTED_GPU_NAMES="${gpu_names[*]:-unknown}"

    return 0
}

# ====================== SMART BUILD STRATEGY (CPU-based) ======================
decide_build_strategy() {
    log_info "Determining optimal build strategy based on CPU capabilities..."

    # --- Проверяем возможности CPU через /proc/cpuinfo ---
    local has_avx2=false
    local has_avx512=false
    local has_avx512_vbmi=false
    local has_avx512_vnni=false
    local has_avx512_bf16=false
    local has_f16c=false

    if grep -q "avx2" /proc/cpuinfo 2>/dev/null; then
        has_avx2=true
    fi

    if grep -q "avx512f" /proc/cpuinfo 2>/dev/null; then
        has_avx512=true
    fi

    if ${has_avx512}; then
        grep -q "avx512vbmi" /proc/cpuinfo 2>/dev/null && has_avx512_vbmi=true
        grep -q "avx512vnni" /proc/cpuinfo 2>/dev/null && has_avx512_vnni=true
        grep -q "avx512bf16" /proc/cpuinfo 2>/dev/null && has_avx512_bf16=true
        grep -q "f16c" /proc/cpuinfo 2>/dev/null && has_f16c=true
    fi

    # --- Вывод диагностики ---
    echo ""
    echo "Processor: $(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)"
    echo "Cores: $(nproc)"
    echo "CPU Capabilities detected:"
    echo "   AVX2          : ${has_avx2}"
    echo "   AVX512        : ${has_avx512}"
    echo "   AVX512_VBMI   : ${has_avx512_vbmi}"
    echo "   AVX512_VNNI   : ${has_avx512_vnni}"
    echo "   AVX512_BF16   : ${has_avx512_bf16}"
    echo "   F16C          : ${has_f16c}"
    echo ""

    # --- Принимаем решение ---
    if ${has_avx512}; then
        log_info "AVX512-capable CPU detected → enabling aggressive optimizations"
        GGML_NATIVE="ON"

        # Формируем дополнительные CMake флаги
        CMAKE_EXTRA_FLAGS=(
            "-DGGML_AVX512=ON"
        )

        ${has_avx512_vbmi} && CMAKE_EXTRA_FLAGS+=("-DGGML_AVX512_VBMI=ON")
        ${has_avx512_vnni} && CMAKE_EXTRA_FLAGS+=("-DGGML_AVX512_VNNI=ON")
        ${has_avx512_bf16} && CMAKE_EXTRA_FLAGS+=("-DGGML_AVX512_BF16=ON")
        ${has_f16c}        && CMAKE_EXTRA_FLAGS+=("-DGGML_F16C=ON")

        log_success "Applied AVX512 optimizations:"
        for flag in "${CMAKE_EXTRA_FLAGS[@]}"; do
            log_info "   ${flag}"
        done

    elif ${has_avx2}; then
        log_info "AVX2-capable CPU detected → GGML_NATIVE=ON"
        GGML_NATIVE="ON"
        CMAKE_EXTRA_FLAGS=("-DGGML_AVX2=ON" "-DGGML_F16C=ON")
    else
        log_info "Old CPU detected (no AVX2) → GGML_NATIVE=OFF for compatibility"
        GGML_NATIVE="OFF"
        CMAKE_EXTRA_FLAGS=()
    fi

    # --- Позволяем пользователю переопределить ---
    read -p "Use this configuration? [Y/n] " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "  [1] GGML_NATIVE=OFF (maximum compatibility)"
        echo "  [2] GGML_NATIVE=ON  (best performance)"
        read -p "Select [2]: " choice
        [[ "$choice" == "1" ]] && GGML_NATIVE="OFF"
        [[ "$choice" == "2" ]] && GGML_NATIVE="ON"
    fi

    log_info "Final decision: GGML_NATIVE=${GGML_NATIVE}"
    
    # --- Check for Multi-Arch GPUs ---
    local arch_count=$(echo "$CMAKE_CUDA_ARCHITECTURES" | tr ';' '\n' | wc -l)
    
    if [[ $arch_count -gt 1 ]]; then
        echo ""
        echo "Multiple GPU architectures detected: ${CMAKE_CUDA_ARCHITECTURES}"
        echo "Please select build strategy:"
        echo "  [1] Single binary with all architectures (Default)"
        echo "  [2] Separate binaries for each architecture + Universal binary"
        read -p "Choice [1]: " multi_arch_choice
        multi_arch_choice=${multi_arch_choice:-1}
        
        if [[ "$multi_arch_choice" == "2" ]]; then
            BUILD_MULTIARCH_MODE="ON"
            log_info "Multi-architecture build mode enabled."
        else
            BUILD_MULTIARCH_MODE="OFF"
            log_info "Single binary build mode selected."
        fi
    else
        BUILD_MULTIARCH_MODE="OFF"
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
        return 0
    else
        log_error "Failed to install Node.js. You can install it manually later."
        return 1
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
        else
            SCRIPT_STATE["SERVICE_ACTIVE"]=false
            log_warn "Service ${SERVICE_NAME} exists but is INACTIVE"
        fi
        save_service_config "$SERVICE_NAME"   # Автосохранение
    else
        log_warn "Service unit '${SERVICE_NAME}' not found in systemd"
    fi
}

stop_service() {
    if ${SCRIPT_STATE["SERVICE_ACTIVE"]}; then
        log_info "Stopping service ${SERVICE_NAME}..."
        sudo systemctl stop "$SERVICE_NAME" || { log_error "Failed to stop service"; return 1; }
        SERVICE_WAS_STOPPED=true
    fi
    return 0
}

start_service() {
    if ${SCRIPT_STATE["SERVICE_ACTIVE"]}; then
        log_info "Starting service ${SERVICE_NAME}..."
        sudo systemctl start "$SERVICE_NAME"
        sleep 3
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            log_success "Service started successfully"
            return 0
        else
            log_error "Failed to start service"
            return 1
        fi
    else
        log_warn "Service is not active/configured, skipping start."
        return 0
    fi
}

display_service_status() {
    log_info "Displaying service status..."
    echo ""
    echo "=== SERVICE STATUS: ${SERVICE_NAME} ==="
    echo ""
    sudo systemctl status "${SERVICE_NAME}" --no-pager -l
    echo ""
    return 0
}

# ====================== BUILD HISTORY (CLEANED FORMAT) ======================
save_build_log() {
    mkdir -p "${BACKUP_DIR}"
    
    # Получаем текущий коммит и дату
    local commit=$(cd "${REPO_DIR}" 2>/dev/null && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local commit_date=$(cd "${REPO_DIR}" 2>/dev/null && git show -s --format=%ci HEAD 2>/dev/null || echo "unknown")
    local build_date=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Получаем информацию о системе
    local driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 2>/dev/null || echo 'unknown')
    local gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1 2>/dev/null || echo 'unknown')
    
    # Формируем полный набор ключей сборки
    local cmake_flags_line="CMake flags: ${BUILD_CMAKE_ARGS}"
    local make_flags_line="Make flags: ${BUILD_MAKE_ARGS}"
    local cuda_version_line="CUDA Toolkit: ${REQUIRED_CUDA}"
    
    {
        echo "=================================================="
        echo "Build Record: ${build_date}"
        echo "=================================================="
        echo "Commit: ${commit}"
        echo "Commit Date: ${commit_date}"
        echo "--------------------------------------------------"
        echo "System Information:"
        echo "  GPUs: ${DETECTED_GPU_NAMES:-unknown}"
        echo "  Driver: ${driver_version}"
        echo "  ${cuda_version_line}"
        echo "--------------------------------------------------"
        echo "Full Compilation Flags:"
        echo "  ${cmake_flags_line}"
        echo "  ${make_flags_line}"
        echo "=================================================="
        echo ""
    } >> "${BUILD_HISTORY}"
    
    log_info "Build record saved to ${BUILD_HISTORY}"
}

# ====================== BACKUP & RESTORE ======================
create_backup() {
    mkdir -p "${BACKUP_DIR}"
    
    # Получаем текущий коммит и дату для имени бэкапа
    local current_commit=$(cd "${REPO_DIR}" 2>/dev/null && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    
    # Get commit date in ISO format: YYYY-MM-DD HH:MM:SS +ZZZZ
    # Then convert to: YYYY-MM-DD_HH-MM-SS+ZZZZ
    local raw_commit_date=$(cd "${REPO_DIR}" 2>/dev/null && git show -s --format=%ai HEAD 2>/dev/null || echo "unknown")
    local commit_date=""
    
    if [[ "$raw_commit_date" != "unknown" ]]; then
                commit_date=$(echo "$raw_commit_date" | sed 's/:/-/g; s/ /_/; s/ //')
    else
        commit_date="unknown"
    fi
    
    local backup_date=$(date '+%Y-%m-%d_%H-%M-%S')
    
    # New naming format: backup_YYYY-MM-DD_HH-MM-SS_HASH_COMMITDATE
    local backup_name="backup_${backup_date}_${current_commit}_${commit_date}"
    local backup_path="${BACKUP_DIR}/${backup_name}"

    # Check for existing backup with same commit hash
    # We search for any directory in BACKUP_DIR that contains the commit hash in its name.
    # This covers both old formats (ending in _HASH) and new formats (containing _HASH_).
    local existing_backup=""
    
    # Use find to list directories, then grep to filter by hash presence
    # The regex ensures we match the hash as a distinct part (preceded/followed by underscore or end of string)
    # However, simple substring check is usually sufficient if hashes are unique enough.
    # To be safe against partial matches (e.g. hash 'abc' matching 'abcd'), we rely on the fact that
    # git short hashes are 7 chars and unlikely to collide with other parts of the filename structure.
    # A more precise grep would be: grep -E "_${current_commit}(_|$)"
    
    while IFS= read -r dir; do
        if [[ -n "$dir" ]]; then
            existing_backup="$dir"
                    break
                fi
    done < <(find "${BACKUP_DIR}" -mindepth 1 -maxdepth 1 -type d -name "*_${current_commit}*" | head -n 1)

    if [[ -n "$existing_backup" ]]; then
        log_warn "A backup for commit ${current_commit} already exists:"
        log_warn "  $(basename "$existing_backup")"
        read -p "Create another backup for this commit? [y/N] " dup_choice
        if [[ ! "$dup_choice" =~ ^[Yy]$ ]]; then
            log_info "Skipping backup creation as requested."
            LAST_BACKUP_PATH="$existing_backup"
            return 0
        fi
    fi

    log_info "Creating backup → ${backup_path}"
    # Store path globally for potential rollback
    LAST_BACKUP_PATH="$backup_path"

    if cp -ra "${REPO_DIR}" "${backup_path}" 2>/dev/null; then
        log_success "Backup created: ${backup_name}"

        # Keep only last 10 backups
        find "${BACKUP_DIR}" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | \
            sort -rn | tail -n +11 | cut -d' ' -f2- | xargs -r rm -rf
        return 0
    else
        log_error "Backup failed"
        return 1
    fi
}

list_backups() {
    echo ""
    echo "Available backups:"
    echo "----------------------------------------"
    printf "%-3s %-30s %-15s\n" "ID" "Name" "Size"
    echo "----------------------------------------"
    local count=0
    while IFS= read -r line; do
        ((count++))
        # Извлекаем только путь (вторая часть строки после timestamp)
        local dir=$(echo "$line" | awk '{print $2}')
        local name=$(basename "$dir")
        local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        printf "%-3s %-30s %-15s\n" "$count" "$name" "$size"
    done < <(find "${BACKUP_DIR}" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -rn)
    [[ $count -gt 0 ]]
}

restore_backup_interactive() {
    if ! list_backups; then return 1; fi

    read -p "Select backup ID to restore (1-10): " selected_id
    local target_backup=""
    local count=0

    while IFS= read -r line; do
        ((count++))
        if [[ $count -eq $selected_id ]]; then
            # ИЗВЛЕКАЕМ ТОЛЬКО ПУТЬ (вторая часть строки)
            target_backup=$(echo "$line" | awk '{print $2}')
            break
        fi
    done < <(find "${BACKUP_DIR}" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -rn)

    if [ -z "$target_backup" ]; then
        log_error "Invalid backup ID"
        return 1
    fi

    log_info "Selected backup: $(basename "$target_backup")"
    log_info "Backup path: $target_backup"

    if [ ! -d "$target_backup" ]; then
        log_error "Backup directory does not exist: $target_backup"
        return 1
    fi

    read -p "Restore $(basename "$target_backup")? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || return 0

    log_info "Removing existing repo directory..."
    rm -rf "${REPO_DIR}"
    
    log_info "Copying backup to ${REPO_DIR}..."
    if cp -ra "$target_backup" "${REPO_DIR}" 2>&1; then
        log_success "Successfully restored from $(basename "$target_backup")"
        
        # Проверка: существует ли каталог после копирования
        if [ -d "$REPO_DIR" ]; then
            log_success "Verification: ${REPO_DIR} exists"
            return 0
        else
            log_error "Verification failed: ${REPO_DIR} does not exist after copy"
            return 1
        fi
    else
        log_error "Failed to copy backup to ${REPO_DIR}"
        return 1
    fi
}

# Restore specific backup path (used for automatic rollback)
restore_backup_path() {
    local path="$1"
    if [ -z "$path" ] || [ ! -d "$path" ]; then
        log_error "No valid backup path provided for rollback"
        return 1
    fi

    log_warn "Rolling back to: $(basename "$path")"
    rm -rf "${REPO_DIR}"
    cp -ra "$path" "${REPO_DIR}"
    log_success "Rollback completed"
    return 0
}

# ====================== GIT ======================
git_checkout_target() {
    local target="${1:-latest}"
    cd "${REPO_DIR}" || { log_error "Cannot cd to repo"; return 1; }

    if [[ "$target" == "latest" ]]; then
        log_info "Pulling latest version..."
        git fetch --all --prune
        
        # Check if local is already up-to-date with remote
        local local_head=$(git rev-parse HEAD)
        local remote_master=$(git rev-parse origin/master 2>/dev/null || git rev-parse origin/main 2>/dev/null)
        
        if [[ "$local_head" == "$remote_master" ]]; then
            log_info "Local version is already up-to-date with remote."
            read -p "Rebuild anyway? [y/N] " rebuild_choice
            if [[ "$rebuild_choice" =~ ^[Nn]$ ]]; then
                log_info "Exiting without changes."
                exit 0
            fi
        fi
        git reset --hard origin/master 2>/dev/null || git reset --hard origin/main
        git pull origin master 2>/dev/null || git pull origin main
        log_success "Latest master/main checked out"
    elif [[ "$target" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        log_info "Rolling back to date: $target"
        git fetch --all
        
        # ИСПРАВЛЕНО: Используем --until вместо --before
        local commit=$(git rev-list -n 1 --until="$target 23:59:59" origin/master 2>/dev/null || \
                       git rev-list -n 1 --until="$target 23:59:59" origin/main)
        
        if [ -z "$commit" ]; then
            log_error "No commit found for date $target"
            return 1
        fi
        
        # Показать реальную дату коммита
        local commit_date=$(git show -s --format=%cd --date=short "$commit")
        log_success "Rolled back to commit from $commit_date"
        
        git reset --hard "$commit"
    else
        log_info "Checking out commit: $target"
        git reset --hard "$target"
    fi
    return 0
}

# ====================== DRIVER INSTALLATION ======================
ensure_nvidia_driver() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        log_success "NVIDIA driver already installed"
        return 0
    fi

    log_warn "NVIDIA driver not found"
    read -p "Automatically install NVIDIA driver ${REQUIRED_DRIVER}? [y/n] " choice
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
    cd "${REPO_DIR}" || { log_error "Cannot cd to repo directory: ${REPO_DIR}"; return 1; }
    local cuda_path="/usr/local/cuda-${REQUIRED_CUDA}"
    local nvcc_path="${cuda_path}/bin/nvcc"

    # === КРИТИЧНЫЕ ПАРАМЕТРЫ ДЛЯ CUDA ===
    if [ ! -x "$nvcc_path" ]; then
        log_error "nvcc not found at $nvcc_path"
        log_error "Please check CUDA installation"
        return 1
    fi

    # Clean old builds
    rm -rf "${REPO_DIR}/build" "${REPO_DIR}/build_*"

    # 1. Perform Primary Build (Universal or Single Arch)
    local build_dir="${REPO_DIR}/build"
    mkdir -p "$build_dir"

    log_info "Using nvcc: $nvcc_path"
    log_info "Building with architectures: ${CMAKE_CUDA_ARCHITECTURES}"
    log_info "Build strategy: (GGML_NATIVE=${GGML_NATIVE})"

    # Собираем все флаги CMake для логирования
    local cmake_args="-DCMAKE_CUDA_COMPILER=${nvcc_path} \
        -DCMAKE_CUDA_ARCHITECTURES=${CMAKE_CUDA_ARCHITECTURES} \
        -DGGML_CUDA=ON \
        -DGGML_CURL=ON \
        -DGGML_CUDA_FA_ALL_QUANTS=ON \
        -DGGML_NATIVE=${GGML_NATIVE} \
        -DCMAKE_CUDA_FLAGS=-Wno-deprecated-gpu-targets \
        -DCMAKE_BUILD_TYPE=Release"

    # Add CPU-specific flags if any
    local extra_flags_log=""
    for flag in "${CMAKE_EXTRA_FLAGS[@]}"; do
        cmake_args+=" ${flag}"
        extra_flags_log+="${flag} "
    done

    # Сохраняем флаги для логирования
    BUILD_CMAKE_ARGS="$cmake_args"
    BUILD_MAKE_ARGS="-j$(nproc) --target llama-cli llama-server llama-gguf-split"
    BUILD_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    BUILD_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    BUILD_COMMIT_DATE=$(git show -s --format=%ci HEAD 2>/dev/null || echo "unknown")
    
    log_info "Starting primary compilation..."
    log_info "Build timestamp: ${BUILD_TIMESTAMP}"
    log_info "Commit: ${BUILD_COMMIT} (${BUILD_COMMIT_DATE})"
    log_info "CMake flags: ${BUILD_CMAKE_ARGS}"
    log_info "Make flags: ${BUILD_MAKE_ARGS}"

    cmake -S . -B "$build_dir" \
        -DCMAKE_CUDA_COMPILER="${nvcc_path}" \
        -DCMAKE_CUDA_ARCHITECTURES="${CMAKE_CUDA_ARCHITECTURES}" \
        -DGGML_CUDA=ON \
        -DGGML_CURL=ON \
        -DGGML_CUDA_FA_ALL_QUANTS=ON \
        -DGGML_NATIVE=${GGML_NATIVE} \
        -DCMAKE_CUDA_FLAGS="-Wno-deprecated-gpu-targets" \
        -DCMAKE_BUILD_TYPE=Release \
        ${CMAKE_EXTRA_FLAGS[@]} \
        || { log_error "Primary CMake failed"; return 1; }

    cmake --build "$build_dir" --config Release -j$(nproc) \
        --target llama-cli llama-server llama-gguf-split \
        || { log_error "Primary Build failed"; return 1; }

    log_success "Primary build completed successfully"

    # 2. Perform Multi-Arch Builds if enabled
    if [[ "$BUILD_MULTIARCH_MODE" == "ON" ]]; then
        log_step "Building specific architecture binaries..."
        
        IFS=';' read -ra ARCHS <<< "$CMAKE_CUDA_ARCHITECTURES"
        
        for arch in "${ARCHS[@]}"; do
            log_info "Building for architecture: ${arch}"
            local specific_build_dir="${REPO_DIR}/build_${arch}"
            mkdir -p "$specific_build_dir"
            
            # Build command for specific arch
            cmake -S . -B "$specific_build_dir" \
                -DCMAKE_CUDA_COMPILER="${nvcc_path}" \
                -DCMAKE_CUDA_ARCHITECTURES="${arch}" \
                -DGGML_CUDA=ON \
                -DGGML_CURL=ON \
                -DGGML_CUDA_FA_ALL_QUANTS=ON \
                -DGGML_NATIVE=${GGML_NATIVE} \
                -DCMAKE_CUDA_FLAGS="-Wno-deprecated-gpu-targets" \
                -DCMAKE_BUILD_TYPE=Release \
                ${CMAKE_EXTRA_FLAGS[@]} \
                || { log_error "CMake failed for arch ${arch}"; return 1; }

            cmake --build "$specific_build_dir" --config Release -j$(nproc) \
                --target llama-server \
                || { log_error "Build failed for arch ${arch}"; return 1; }
            
            # Rename the binary to include architecture suffix
            local src_bin="${specific_build_dir}/bin/llama-server"
            local dst_bin="${specific_build_dir}/bin/llama-server-${arch}"
            
            if [ -f "$src_bin" ]; then
                mv "$src_bin" "$dst_bin"
                chmod +x "$dst_bin"
                log_success "Created specific binary: llama-server-${arch}"
            else
                log_warn "Binary not found for arch ${arch}. Skipping rename."
            fi
        done
        
        # Output summary for multi-arch builds ONLY if multiple architectures were built
        local arch_count=$(echo "${ARCHS[@]}" | wc -w)
        if [[ $arch_count -gt 1 ]]; then
        echo ""
        echo "=================================================="
        echo "MULTI-ARCHITECTURE BUILD SUMMARY"
        echo "=================================================="
        echo "Universal binary (all archs) deployed:" 
        echo "from ${REPO_DIR}/build/bin/llama-server to ${SCRIPT_BASENAME}/llama-server"
        echo "To deploy specific architecture binaries, use the following commands:"
        for arch in "${ARCHS[@]}"; do
            local specific_build_dir="${REPO_DIR}/build_${arch}"
            local specific_bin="${specific_build_dir}/bin/llama-server-${arch}"
            if [ -f "$specific_bin" ]; then
                echo "  cp ${specific_bin} ${SCRIPT_BASENAME}"
            fi
        done
        echo "=================================================="
    fi
    fi

    log_success "Build completed successfully"
    return 0
}

# ====================== DEPLOYMENT WITH DETAILED DIAGNOSTICS ======================
deploy_binaries() {
    local src_dir="${REPO_DIR}/build/bin"
    local dst_dir="${SCRIPT_BASENAME}"
    
    # === DIAGNOSTIC: Check source directory ===
    if [ ! -d "$src_dir" ]; then
        DEPLOY_ERROR_REASON="SOURCE_NOT_FOUND"
        DEPLOY_ERROR_DETAILS="Build output directory does not exist: $src_dir"
        log_error "Deployment failed: Source directory not found"
        log_error "Details: $DEPLOY_ERROR_DETAILS"
        log_error "Possible causes:"
        log_error "  1. Build failed silently - check build log above"
        log_error "  2. Build targets not specified - check CMake configuration"
        log_error "  3. Wrong path - expected: $src_dir"
        return 1
    fi

    # === DIAGNOSTIC: Check if source has files ===
    local source_files=$(find "$src_dir" -type f -name "llama-*" 2>/dev/null | head -n 5)
    if [ -z "$source_files" ]; then
        DEPLOY_ERROR_REASON="NO_BINARIES"
        DEPLOY_ERROR_DETAILS="No llama-* binaries found in source directory"
        log_error "Deployment failed: No binaries found in source"
        log_error "Details: $DEPLOY_ERROR_DETAILS"
        log_error "Possible causes:"
        log_error "  1. Build completed but didn't create expected binaries"
        log_error "  2. Wrong build targets - check CMake targets"
        log_error "  3. Try: ls -la $src_dir"
        return 1
    fi

    # === DIAGNOSTIC: Check destination directory exists ===
    if [ ! -d "$dst_dir" ]; then
        DEPLOY_ERROR_REASON="DEST_NOT_FOUND"
        DEPLOY_ERROR_DETAILS="Destination directory does not exist: $dst_dir"
        log_error "Deployment failed: Destination directory not found"
        log_error "Details: $DEPLOY_ERROR_DETAILS"
        log_error "Possible causes:"
        log_error "  1. Directory was deleted - recreate: sudo mkdir -p $dst_dir"
        log_error "  2. Wrong path in configuration"
        log_error "  3. Try: sudo mkdir -p $dst_dir && sudo chmod 755 $dst_dir"
        return 1
    fi

    # === DIAGNOSTIC: Check write permissions ===
    if ! touch "$dst_dir/.test_write" 2>/dev/null; then
        DEPLOY_ERROR_REASON="NO_WRITE_PERMISSION"
        DEPLOY_ERROR_DETAILS="Cannot write to destination directory: $dst_dir"
        log_error "Deployment failed: No write permission"
        log_error "Details: $DEPLOY_ERROR_DETAILS"
        log_error "Possible causes:"
        log_error "  1. Directory owned by another user - check with: ls -la $dst_dir"
        log_error "  2. Script not run as root - try: sudo $0"
        log_error "  3. Fix permissions: sudo chown -R $USER:$USER $dst_dir"
        return 1
    fi
    rm -f "$dst_dir/.test_write"

    # === DIAGNOSTIC: Check if destination files are locked ===
    local locked_files=()
    for file in "$dst_dir"/llama-*; do
        if [ -f "$file" ]; then
            # Check if file is in use (on Linux, check if it's open by any process)
            if lsof "$file" >/dev/null 2>&1; then
                locked_files+=("$(basename "$file")")
            fi
        fi
    done

    if [[ ${#locked_files[@]} -gt 0 ]]; then
        DEPLOY_ERROR_REASON="FILES_LOCKED"
        DEPLOY_ERROR_DETAILS="Files in use by other processes: ${locked_files[*]}"
        log_error "Deployment failed: Files are locked by other processes"
        log_error "Details: $DEPLOY_ERROR_DETAILS"
        log_error "Possible causes:"
        log_error "  1. Service is still running - try: sudo systemctl stop $SERVICE_NAME"
        log_error "  2. Binary is running in another terminal"
        log_error "  3. Force stop: sudo killall llama-*"
        log_error "  4. Check with: sudo lsof $dst_dir/llama-*"
        return 1
    fi

    # === DIAGNOSTIC: Check disk space ===
    local available_space=$(df -k "$dst_dir" | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt 10000 ]; then  # Less than 10MB
        DEPLOY_ERROR_REASON="LOW_DISK_SPACE"
        DEPLOY_ERROR_DETAILS="Low disk space: ${available_space}KB available"
        log_error "Deployment failed: Insufficient disk space"
        log_error "Details: $DEPLOY_ERROR_DETAILS"
        log_error "Possible causes:"
        log_error "  1. Disk is full - free space: sudo apt-get autoremove"
        log_error "  2. Check with: df -h"
        return 1
    fi

    # === DIAGNOSTIC: Attempt copy with detailed error capture ===
    log_info "Deploying binaries from $src_dir to $dst_dir"
    local copied_count=0
    local failed_bins=()

    for src_file in "${src_dir}"/llama-*; do
        [ -f "$src_file" ] || continue
        local bin_name=$(basename "$src_file")
        local dst_file="${dst_dir}/${bin_name}"

        # SYMLINK HANDLING: Check if destination is a symlink pointing to source build dir
        if [ -L "$dst_file" ]; then
            local link_target=$(readlink -f "$dst_file" 2>/dev/null)
            local src_resolved=$(readlink -f "$src_file" 2>/dev/null)
            
            # Handle broken symlinks
            if [ ! -e "$dst_file" ]; then
                log_warn "Broken symlink detected: ${bin_name} → removing"
                rm -f "$dst_file"
            elif [ -n "$link_target" ] && [ "$link_target" = "$src_resolved" ]; then
                log_info "Skipped copy: ${bin_name} is a valid symlink to build dir"
                # Ensure executable permission on target
                if [ ! -x "$dst_file" ]; then
                    chmod +x "$dst_file" 2>/dev/null || true
                fi
                ((copied_count++))
                continue
            fi
        fi

        # Standard deployment for non-symlink or mismatched symlink
        local cp_err=""
        cp_err=$(cp -f "$src_file" "$dst_file" 2>&1) || {
            log_error "Failed to copy ${bin_name}: $cp_err"
            failed_bins+=("$bin_name")
            continue
        }
        chmod +x "$dst_file"
        ((copied_count++))
    done

    if [[ ${#failed_bins[@]} -gt 0 ]]; then
        DEPLOY_ERROR_REASON="COPY_FAILED"
        DEPLOY_ERROR_DETAILS="Copy failed with error: Failed to deploy: ${failed_bins[*]}"
        log_error "Deployment failed: Copy operation failed"
        log_error "Details: $DEPLOY_ERROR_DETAILS"
        log_error "Possible causes:"
        log_error "  1. Permission issues - try: sudo chown -R root:root /opt/llm"
        log_error "  2. File system is read-only - check: mount | grep /opt/llm"
        log_error "  3. Try manual copy: sudo cp -f /opt/llm/llama.cpp/build/bin/llama-* /opt/llm/"
        return 1
    fi

    # === DIAGNOSTIC: Verify files were copied ===
    local copied_count_final=0
    for file in "${dst_dir}"/llama-*; do
        if [ -f "$file" ]; then
            ((copied_count_final++))
        fi
    done

    if [ $copied_count_final -eq 0 ]; then
        DEPLOY_ERROR_REASON="NO_FILES_COPIED"
        DEPLOY_ERROR_DETAILS="No files were copied despite successful command"
        log_error "Deployment failed: No files were copied"
        log_error "Details: $DEPLOY_ERROR_DETAILS"
        log_error "Possible causes:"
        log_error "  1. Source pattern didn't match - check: ls $src_dir/llama-*"
        log_error "  2. Try manual copy: sudo cp -f $src_dir/llama-* $dst_dir/"
        return 1
    fi

    log_success "Binaries deployed to ${SCRIPT_BASENAME} (${copied_count_final} files)"
    return 0
}

# ====================== VERIFICATION & HEALTH CHECK ======================
verify_binaries() {
    log_info "Verifying deployed binaries..."
    local binary_path="${SCRIPT_BASENAME}/llama-cli"
    
    if [ ! -x "$binary_path" ]; then
        log_error "Binary not found or not executable: $binary_path"
        log_error "Check: ls -la $binary_path"
        return 1
    fi

    # Quick health check
    if "$binary_path" --version >/dev/null 2>&1; then
        log_success "Binary verification passed (--version)"
        return 0
    else
        log_error "Binary execution failed (health check)"
        log_error "Try: $binary_path --help"
        return 1
    fi
}

# ====================== ROLLBACK COMPLETION (NEW) ======================
complete_rollback() {
    # Step 1: Deploy binaries from restored source
    log_step "Completing rollback: Deploying binaries..."
    if ! deploy_binaries; then
        log_error "Rollback deployment failed"
        handle_deployment_failure
        return 1
    fi

    # Step 2: Verify binaries
    if ! verify_binaries; then
        log_error "Rollback verification failed"
        return 1
    fi

    # Step 3: Start service if it was stopped
    if [ "$SERVICE_WAS_STOPPED" = "true" ] || ${SCRIPT_STATE["SERVICE_ACTIVE"]}; then
        if ! start_service; then
            log_error "Service start failed after rollback"
            return 1
        fi
    fi

    # Step 4: Display service status
    display_service_status

    log_success "Rollback completed successfully"
    return 0
}

# ====================== DEPLOYMENT RECOVERY ======================
handle_deployment_failure() {
    echo ""
    log_error "Deployment failed"
    echo ""
    echo "Error details:"
    echo "  Reason: $DEPLOY_ERROR_REASON"
    echo "  Details: $DEPLOY_ERROR_DETAILS"
    echo ""
    echo "Recommended fixes:"
    case "$DEPLOY_ERROR_REASON" in
        SOURCE_NOT_FOUND|NO_BINARIES)
            echo "  1. Check build log above for errors"
            echo "  2. Verify build completed successfully"
            echo "  3. Try rebuilding: sudo $0"
            ;;
        DEST_NOT_FOUND)
            echo "  1. Create directory: sudo mkdir -p $SCRIPT_BASENAME"
            echo "  2. Set permissions: sudo chmod 755 $SCRIPT_BASENAME"
            ;;
        NO_WRITE_PERMISSION|COPY_PERMISSION_DENIED)
            echo "  1. Check ownership: ls -la $SCRIPT_BASENAME"
            echo "  2. Fix permissions: sudo chown -R \$USER:\$USER $SCRIPT_BASENAME"
            echo "  3. Or run script as root: sudo $0"
            ;;
        FILES_LOCKED)
            echo "  1. Stop service: sudo systemctl stop $SERVICE_NAME"
            echo "  2. Kill processes: sudo killall llama-*"
            echo "  3. Check with: sudo lsof $SCRIPT_BASENAME/llama-*"
            ;;
        LOW_DISK_SPACE)
            echo "  1. Free space: sudo apt-get autoremove"
            echo "  2. Check disk: df -h"
            ;;
        *)
            echo "  1. Check error details above"
            echo "  2. Try manual deployment: sudo cp -f $REPO_DIR/build/bin/llama-* $SCRIPT_BASENAME/"
            ;;
    esac
    echo ""
    echo "Options:"
    echo "  [1] Retry deployment (after fixing the issue)"
    echo "  [2] Restore from backup and exit"
    echo "  [3] Exit without changes"
    read -p "Choice [1]: " retry_choice
    retry_choice=${retry_choice:-1}

    case "$retry_choice" in
        1)
            log_info "Returning to main menu to retry..."
            return 0
            ;;
        2)
            if [ -n "$LAST_BACKUP_PATH" ] && [ -d "$LAST_BACKUP_PATH" ]; then
                log_info "Restoring backup..."
                restore_backup_path "$LAST_BACKUP_PATH"
                return 1
            else
                log_error "No backup available"
                return 1
            fi
            ;;
        3)
            log_info "Exiting without changes"
            return 1
            ;;
        *)
            log_error "Invalid choice"
            return 1
            ;;
    esac
}

# ====================== MAIN ENTRY POINT ======================
main() {
    echo "=================================================="
    echo "    LLM Update Script v${SCRIPT_VERSION} — DFD Compliant"
    echo "    Repo: ${REPO_DIR}"
    echo "=================================================="

    # Acquire lock before any operation
    acquire_lock || exit 1

    load_service_config

   check_all_requirements || { log_error "Requirements check failed."; release_lock; exit 1; }

    # Check build tools
    check_build_tools || { log_error "Build tools check failed."; release_lock; exit 1; }

    # GPU detection
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
            
            # 1. Stop Service
            if ! stop_service; then
                log_error "Failed to stop service"
                release_lock
                exit 1
            fi

            # 2. Create Backup
            if ! create_backup; then
                log_error "Failed to create backup"
                release_lock
                exit 1
            fi

            # 3. Git Checkout / Rebuild Selection
            echo ""
            echo "Select version to build:"
            local current_commit=$(cd "${REPO_DIR}" 2>/dev/null && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
            echo "  [1] Latest (master)"
            echo "  [2] By date (YYYY-MM-DD)"
            echo "  [3] By commit"
            echo "  [4] Rebuild current version (${current_commit})"
            echo "  [5] Exit"
            read -p "Choice [1]: " git_choice
            git_choice=${git_choice:-1}

            local git_target="latest"
            local skip_git_checkout=false

            case "$git_choice" in
                2)
                    read -p "Enter date (YYYY-MM-DD): " git_target
                    ;;
                3)
                    read -p "Enter commit hash: " git_target
                    ;;
                4)
                    skip_git_checkout=true
                    log_info "Skipping Git checkout. Rebuilding current version: ${current_commit}"
                    ;;
                5)
                    log_info "Exiting without changes"
                    release_lock
                    exit 0
                    ;;
                *)
                    git_target="latest"
                    ;;
            esac

            if ! $skip_git_checkout; then
                if ! git_checkout_target "$git_target"; then
                    log_error "Git checkout failed"
                    handle_update_failure
                    release_lock
                    exit 1
                fi
            fi

    # Decide build strategy for mixed GPUs / CPU capabilities
    decide_build_strategy

            # 4. Build
            log_info "Starting build..."
            if ! perform_build; then
                log_error "Build failed"
                handle_update_failure
                release_lock
                exit 1
            fi

            # 5. Deploy
            log_info "Starting deployment..."
            if ! deploy_binaries; then
                log_error "Deployment failed"
                handle_deployment_failure
                release_lock
                exit 1
            fi

            # 6. Verify Binaries
            if ! verify_binaries; then
                log_error "Binary verification failed"
                handle_update_failure
                release_lock
                exit 1
            fi

            # 7. Save Log (CLEANED FORMAT)
            save_build_log

            # 8. Start Service
            if ! start_service; then
                log_error "Service start failed"
                handle_update_failure
                release_lock
                exit 1
            fi

            # 9. Display Service Status
            display_service_status

            release_lock
            log_success "Operation completed successfully"
            ;;

        2)
            log_step "Rollback to previous build"
            
            # Stop service first
            if ! stop_service; then
                log_warn "Failed to stop service (may not be running)"
            fi
            
            # Restore backup
            if ! restore_backup_interactive; then
                log_error "Rollback failed"
                release_lock
                exit 1
            fi
            
            # Complete rollback (deploy, verify, start service)
            if ! complete_rollback; then
                log_error "Rollback completion failed"
                release_lock
                exit 1
            fi
            
            release_lock
            exit 0
            ;;

        3)
            log_info "Exiting without changes"
            release_lock
            exit 0
            ;;

        *)
            log_error "Invalid selection"
            release_lock
            exit 1
            ;;
    esac

}

# Handles failure during Update flow by offering to restore the backup created at start of update
handle_update_failure() {
    echo ""
    log_error "Update process failed at some stage."
    if [ -n "$LAST_BACKUP_PATH" ] && [ -d "$LAST_BACKUP_PATH" ]; then
        log_info "A backup exists at: $LAST_BACKUP_PATH"
        read -p "Restore last backup automatically? [y/N] " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            log_info "Restoring backup..."
            restore_backup_path "$LAST_BACKUP_PATH"
            log_info "Service restart skipped (manual intervention recommended)"
        else
            log_info "Backup preserved. You may restore it manually later."
        fi
    else
        log_warn "No backup available for automatic rollback."
    fi
}

main "$@"
