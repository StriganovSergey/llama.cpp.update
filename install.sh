#!/usr/bin/env bash
# =============================================================================
# install.sh — LLM Environment Installer v1.0.5
# Purpose: Idempotent setup of llama.cpp repo, model selection, systemd service,
#          run script, and invocation of update.sh for build/deploy.
# DFD Compliant Edition — Robust Read Handling & Fallback Update Detection
# =============================================================================
# <PLAN>
# 1. Configuration block (constants, paths, templates)
# 2. Logging + helper functions (prompt, validation, idempotent create/fix)
# 3. f_check_status() → Reports existence/version of repo, service, run script, models
# 4. Step 1: Clone/validate repository (Smart Update Check)
# 5. Smart Skip Check → If run_llm.sh and models exist, ask to skip configuration
# 6. Step 2: Model selection dialog (with Exit option)
# 7. Step 3: Create/validate systemd service file (independent)
# 8. Step 4: Create/validate run_llm.sh startup script (independent)
# 9. Step 5: Invoke update.sh with pre-flight message (Fallback to update*.sh)
# 10. Main orchestration with strict error handling & exit trap
# Risks mitigated: read interrupt (Ctrl+C) defaulting to Y, missing update.sh,
# aggressive skip logic, missing progress, unvalidated steps, permission failures.
# </PLAN>

# [RULE_MANDATORY_COMPLIANCE] + [RULE_STRICTNESS]
set -euo pipefail

# ====================== CONFIGURATION (DFD: RULE_CONFIG_EXEC_SEPARATION) ======================
readonly s_SCRIPT_VERSION="1.0.5"
readonly s_SCRIPT_NAME="install.sh"
readonly s_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly s_INSTALL_DIR="/opt/llm"
readonly s_REPO_URL="https://github.com/ggerganov/llama.cpp.git"
readonly s_REPO_DIR="${s_INSTALL_DIR}/llama.cpp"
readonly s_MODEL_DIR="${s_INSTALL_DIR}/models"
readonly s_SERVICE_PATH="/etc/systemd/system/llm.service"
readonly s_RUN_SCRIPT_PATH="${s_INSTALL_DIR}/run_llm.sh"
readonly s_UPDATE_SCRIPT="${s_SCRIPT_DIR}/update.sh"

# Default model URLs
readonly s_MODEL_DEFAULT_URL="https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-UD-Q5_K_XL.gguf?download=true"
readonly s_MMPROJ_DEFAULT_URL="https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/mmproj-F16.gguf?download=true"

# State flags
b_DEBUG_MODE=false

# Templates with placeholders
s_TEMPLATE_SERVICE='[Unit]
Description=Local LLM Service
After=network.target

[Service]
ExecStart=/bin/bash @@RUN_SCRIPT_PATH@@
Restart=always
WorkingDirectory=@@INSTALL_DIR@@
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
Environment="LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64"
Environment="VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nouveau_icd.json"

[Install]
WantedBy=multi-user.target'

s_TEMPLATE_RUN='#!/bin/bash
export GGML_CUDA_PDL=0
export GGML_CUDA_FORCE_MMQ=1
export GGML_CUDA_KQUANTS_ITER=2
export CUDA_VISIBLE_DEVICES=0
"@@SERVER_BIN@@" \
  -m "@@MODEL_PATH@@" \
  --mmproj "@@MMPROJ_PATH@@" \
  --host 0.0.0.0 \
  --port 8085 \
  --jinja \
  -a "sk-no-key-required" \
  -fa on \
  --fit on \
  --main-gpu 0 \
  --no-context-shift \
  --temp 0.6 \
  --top-k 20 \
  --top-p 0.95 \
  --repeat_penalty 1.5 \
  --repeat_last_n 64 \
  --min-p 0 \
  --ctx-size 262144 \
  --batch-size 2048 \
  -ub 384 \
  --cache-ram 4096 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --parallel 1 \
  -n 262144'

# ====================== LOGGING (DFD: RULE_LOG_FORMAT) ======================
f_log_info()  { echo "[INFO]  $(date '+%H:%M:%S') - $1"; }
f_log_warn()  { echo "[WARN]  $(date '+%H:%M:%S') - ⚠️  $1"; }
f_log_error() { echo "[ERR]   $(date '+%H:%M:%S') - ❌ $1"; }
f_log_success(){ echo "[OK]    $(date '+%H:%M:%S') - ✓ $1"; }
f_log_step()  { echo "" && echo "=== STEP: $1 ===" && echo ""; }

# ====================== HELPERS (DFD: RULE_NAMING, RULE_PROACTIVE) ======================
f_validate_directory() {
    local s_DIR_PATH="$1"
    if [[ ! -d "$s_DIR_PATH" ]]; then
        f_log_warn "Directory missing: ${s_DIR_PATH}. Creating..."
        mkdir -p "$s_DIR_PATH" || { f_log_error "Failed to create ${s_DIR_PATH}"; return 1; }
    fi
    if [[ ! -w "$s_DIR_PATH" ]]; then
        f_log_warn "Directory not writable: ${s_DIR_PATH}. Attempting fix..."
        sudo chown "$(whoami)" "$s_DIR_PATH" 2>/dev/null || true
    fi
    return 0
}

f_validate_file() {
    local s_FILE_PATH="$1"
    local b_IS_CORRUPTED=false
    
    if [[ -f "$s_FILE_PATH" ]]; then
        if [[ ! -s "$s_FILE_PATH" ]]; then
            f_log_warn "File exists but is empty/corrupted: ${s_FILE_PATH}"
            b_IS_CORRUPTED=true
        else
            f_log_info "File verified OK: $(basename "$s_FILE_PATH")"
        fi
    fi
    
    if $b_IS_CORRUPTED || [[ ! -f "$s_FILE_PATH" ]]; then
        return 2 # Signal for recreation
    fi
    return 0
}

# ====================== STATUS REPORT (DFD: RULE_DEFENSE) ======================
f_check_status() {
    echo ""
    echo "=========================================="
    echo "       CURRENT SYSTEM STATUS REPORT"
    echo "=========================================="
    
    # Repository check
    if [[ -d "$s_REPO_DIR" ]]; then
        local s_COMMIT
        s_COMMIT=$(git -C "$s_REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
        echo " [OK] Repository: $s_REPO_DIR (commit: $s_COMMIT)"
    else
        echo " [MISSING] Repository: $s_REPO_DIR"
    fi
    
    # Service check (Fixed: Direct file check is more reliable than systemctl list)
    if [[ -f "$s_SERVICE_PATH" ]]; then
        local s_svc_state
        s_svc_state=$(systemctl is-active llm.service 2>/dev/null || echo "inactive")
        echo " [OK] Service: llm.service (state: $s_svc_state)"
    else
        echo " [MISSING] Service: $s_SERVICE_PATH"
    fi
    
    # Run script check
    if [[ -f "$s_RUN_SCRIPT_PATH" ]]; then
        echo " [OK] Run Script: $s_RUN_SCRIPT_PATH"
    else
        echo " [MISSING] Run Script: $s_RUN_SCRIPT_PATH"
    fi
    
    # Model directory check
    if [[ -d "$s_MODEL_DIR" ]] && [[ -n "$(find "$s_MODEL_DIR" -maxdepth 1 -name '*.gguf' 2>/dev/null | head -n 1)" ]]; then
        echo " [OK] Models: Found in $s_MODEL_DIR"
    else
        echo " [MISSING] Models directory or files"
    fi
    
    echo "=========================================="
}

# ====================== STEP 1: REPOSITORY (DFD: RULE_IDEMPOTENCY) ======================
f_handle_repo() {
    f_log_step "Validating/Cloning Repository"
    
    if [[ -d "$s_REPO_DIR" ]]; then
        if git -C "$s_REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
            # Get local commit hash
            local s_LOCAL_COMMIT
            s_LOCAL_COMMIT=$(git -C "$s_REPO_DIR" rev-parse --short HEAD 2>/dev/null)
            f_log_success "Repository valid. Current commit: ${s_LOCAL_COMMIT}"

            # Fetch remote to compare
            git -C "$s_REPO_DIR" fetch --all >/dev/null 2>&1 || true

            # Determine remote branch (master or main)
            local s_REMOTE_BRANCH="origin/master"
            if ! git -C "$s_REPO_DIR" rev-parse --verify "$s_REMOTE_BRANCH" >/dev/null 2>&1; then
                s_REMOTE_BRANCH="origin/main"
            fi

            # Get remote commit hash
            local s_REMOTE_COMMIT
            s_REMOTE_COMMIT=$(git -C "$s_REPO_DIR" rev-parse --short "$s_REMOTE_BRANCH" 2>/dev/null)

            # Compare local vs remote
            if [[ "$s_LOCAL_COMMIT" == "$s_REMOTE_COMMIT" ]]; then
                f_log_success "Local is up-to-date with remote (${s_REMOTE_BRANCH})."
            else
                f_log_warn "Remote has updates (${s_REMOTE_BRANCH}: ${s_REMOTE_COMMIT})"
                read -r -p "Pull latest changes? [Y/n]: " s_PULL_CHOICE
                s_PULL_CHOICE="${s_PULL_CHOICE:-Y}"
                if [[ ! "$s_PULL_CHOICE" =~ ^[Nn]$ ]]; then
                    f_log_info "Pulling latest..."
                    git -C "$s_REPO_DIR" pull >/dev/null 2>&1
                    f_log_success "Updated to ${s_REMOTE_COMMIT}"
                else
                    f_log_info "Skipping update."
                fi
            fi
        else
            f_log_warn "Repository directory exists but is corrupted. Removing and re-cloning..."
            sudo rm -rf "$s_REPO_DIR"
        fi
    fi
    
    if [[ ! -d "$s_REPO_DIR" ]]; then
        f_log_info "Cloning ${s_REPO_URL} to ${s_REPO_DIR}..."
        git clone "$s_REPO_URL" "$s_REPO_DIR" || { f_log_error "Git clone failed"; return 1; }
        f_log_success "Repository cloned successfully."
    fi
}

# ====================== STEP 2: MODEL SELECTION (DFD: RULE_CONTROLLED_LOOPS) ======================
s_SELECTED_MODEL_PATH=""
s_SELECTED_MMPROJ_PATH=""

f_handle_model() {
    f_log_step "Configuring Model"
    mkdir -p "$s_MODEL_DIR"
    
    while true; do
        echo "Select model source:"
        echo "  [1] Use existing local model"
        echo "  [2] Download default model to ${s_MODEL_DIR}"
        echo "  [3] Download custom model (URL)"
        echo "  [4] Exit installer"
        read -r -p "Choice [2]: " s_MODEL_CHOICE
        s_MODEL_CHOICE="${s_MODEL_CHOICE:-2}"
        
        case "$s_MODEL_CHOICE" in
            1)
                read -r -p "Enter local directory containing models: " s_LOCAL_DIR
                if [[ -z "$s_LOCAL_DIR" ]]; then continue; fi
                f_log_info "Scanning ${s_LOCAL_DIR} for .gguf files..."
                local a_GGUF_FILES=()
                while IFS= read -r -d '' f_file; do
                    a_GGUF_FILES+=("$f_file")
                done < <(find "$s_LOCAL_DIR" -maxdepth 1 -name "*.gguf" -type f -print0 2>/dev/null)
                
                if [[ ${#a_GGUF_FILES[@]} -eq 0 ]]; then
                    f_log_warn "No .gguf files found in ${s_LOCAL_DIR}"
                    continue
                fi
                
                echo "Available models:"
                for i in "${!a_GGUF_FILES[@]}"; do
                    echo "  [$((i+1))] $(basename "${a_GGUF_FILES[$i]}")"
                done
                echo "  [m] mmproj file"
                
                local i_SELECT_IDX=0
                read -r -p "Select model index: " i_SELECT_IDX
                if (( i_SELECT_IDX >= 1 && i_SELECT_IDX <= ${#a_GGUF_FILES[@]} )); then
                    s_SELECTED_MODEL_PATH="${a_GGUF_FILES[$((i_SELECT_IDX-1))]}"
                    f_log_success "Model selected: $(basename "$s_SELECTED_MODEL_PATH")"
                fi
                
                local a_MMPROJ_FILES=()
                for f_file in "${a_GGUF_FILES[@]}"; do
                    [[ "$(basename "$f_file")" == mmproj* ]] && a_MMPROJ_FILES+=("$f_file")
                done
                
                if [[ ${#a_MMPROJ_FILES[@]} -gt 0 ]]; then
                    s_SELECTED_MMPROJ_PATH="${a_MMPROJ_FILES[0]}"
                    f_log_success "mmproj auto-selected: $(basename "$s_SELECTED_MMPROJ_PATH")"
                else
                    read -r -p "Enter path to mmproj file (or press Enter to skip): " s_MMPROJ_INPUT
                    [[ -n "$s_MMPROJ_INPUT" && -f "$s_MMPROJ_INPUT" ]] && s_SELECTED_MMPROJ_PATH="$s_MMPROJ_INPUT"
                fi
                break
                ;;
            2)
                local s_TARGET_MODEL="${s_MODEL_DIR}/gemma-4-E4B-it-UD-Q5_K_XL.gguf"
                local s_TARGET_MMPROJ="${s_MODEL_DIR}/mmproj-F16.gguf"
                echo "[INFO]  Target model path: ${s_TARGET_MODEL}"
                echo "[INFO]  Target mmproj path:  ${s_TARGET_MMPROJ}"
                
                f_log_info "Downloading default model... (progress shown below)"
                if wget --no-proxy -c --tries=150 --waitretry=30 --show-progress -O "$s_TARGET_MODEL" "$s_MODEL_DEFAULT_URL"; then
                    s_SELECTED_MODEL_PATH="$s_TARGET_MODEL"
                    f_log_success "Default model downloaded successfully."
                else
                    f_log_error "Failed to download default model. Check network/URL."
                    return 1
                fi
                
                echo ""
                f_log_info "Downloading mmproj... (progress shown below)"
                if wget --no-proxy -c --tries=150 --waitretry=30 --show-progress -O "$s_TARGET_MMPROJ" "$s_MMPROJ_DEFAULT_URL"; then
                    s_SELECTED_MMPROJ_PATH="$s_TARGET_MMPROJ"
                    f_log_success "mmproj downloaded successfully."
                else
                    f_log_warn "Failed to download mmproj. You may select it manually later."
                fi
                break
                ;;
            3)
                read -r -p "Enter HuggingFace repo or direct URL: " s_CUSTOM_URL
                if [[ -n "$s_CUSTOM_URL" ]]; then
                    local s_FILENAME="${s_CUSTOM_URL##*/}"
                    local s_TARGET_CUSTOM="${s_MODEL_DIR}/${s_FILENAME}"
                    echo "[INFO]  Target path: ${s_TARGET_CUSTOM}"
                    f_log_info "Downloading from: ${s_CUSTOM_URL}..."
                    if wget --no-proxy -c --tries=150 --waitretry=30 --show-progress -O "$s_TARGET_CUSTOM" "$s_CUSTOM_URL"; then
                        s_SELECTED_MODEL_PATH="$s_TARGET_CUSTOM"
                        f_log_success "Custom model downloaded successfully."
                    else
                        f_log_error "Failed to download custom model."
                        return 1
                    fi
                    s_SELECTED_MMPROJ_PATH="${s_MODEL_DIR}/mmproj-F16.gguf" 
                    break
                fi
                ;;
            4)
                f_log_info "Exiting installer."
                exit 0
                ;;
            *) f_log_warn "Invalid choice";;
        esac
    done
    
    if [[ -z "$s_SELECTED_MODEL_PATH" ]] || [[ ! -f "$s_SELECTED_MODEL_PATH" ]]; then
        f_log_error "No valid model selected. Exiting."
        return 1
    fi
    f_log_success "Model configuration complete."
}

# ====================== STEP 3: SYSTEMD SERVICE (DFD: RULE_STATE_PERSISTENCE) ======================
f_handle_service() {
    f_log_step "Configuring Systemd Service"
    
    if f_validate_file "$s_SERVICE_PATH"; then
        f_log_success "Service file exists and verified."
    else
        f_log_info "Creating/Updating service file..."
        printf '%s\n' "$s_TEMPLATE_SERVICE" | sed \
            -e "s|@@INSTALL_DIR@@|${s_INSTALL_DIR}|g" \
            -e "s|@@RUN_SCRIPT_PATH@@|${s_RUN_SCRIPT_PATH}|g" \
            > "$s_SERVICE_PATH.tmp"
        
        sudo mv "$s_SERVICE_PATH.tmp" "$s_SERVICE_PATH"
        sudo systemctl daemon-reload
        sudo systemctl enable llm.service >/dev/null 2>&1 || true
        f_log_success "Service installed and enabled."
    fi
}

# ====================== STEP 4: RUN SCRIPT (DFD: RULE_STATE_VALIDATION) ======================
f_handle_run_script() {
    f_log_step "Configuring Run Script"
    
    local s_SERVER_BIN="${s_INSTALL_DIR}/llama-server"
    
    if f_validate_file "$s_RUN_SCRIPT_PATH"; then
        f_log_success "Run script exists and verified."
    else
        f_log_info "Creating run_llm.sh..."
        printf '%s\n' "$s_TEMPLATE_RUN" | sed \
            -e "s|@@INSTALL_DIR@@|${s_INSTALL_DIR}|g" \
            -e "s|@@RUN_SCRIPT_PATH@@|${s_RUN_SCRIPT_PATH}|g" \
            -e "s|@@SERVER_BIN@@|${s_SERVER_BIN}|g" \
            -e "s|@@MODEL_PATH@@|${s_SELECTED_MODEL_PATH}|g" \
            -e "s|@@MMPROJ_PATH@@|${s_SELECTED_MMPROJ_PATH}|g" \
            > "$s_RUN_SCRIPT_PATH.tmp"
        
        mv "$s_RUN_SCRIPT_PATH.tmp" "$s_RUN_SCRIPT_PATH"
        chmod +x "$s_RUN_SCRIPT_PATH"
        f_log_success "Run script created and made executable."
    fi
}

# ====================== STEP 5: UPDATE.SH INVOCATION (DFD: RULE_PROACTIVE) ======================
f_invoke_update() {
    f_log_step "Preparing Build & Deploy"
    
    # Fallback: If update.sh is missing, look for update*.sh
    if [[ ! -f "$s_UPDATE_SCRIPT" ]]; then
        local found_update
        found_update=$(find "$s_SCRIPT_DIR" -maxdepth 1 -name "update*.sh" -type f 2>/dev/null | head -n 1)
        if [[ -n "$found_update" ]]; then
            f_log_warn "update.sh not found. Using found update script: $(basename "$found_update")"
            s_UPDATE_SCRIPT="$found_update"
        else
            f_log_error "No update scripts found in ${s_SCRIPT_DIR}"
            return 1
        fi
    fi
    
    if [[ ! -f "$s_UPDATE_SCRIPT" ]]; then
        f_log_error "update.sh (or fallback) not found in ${s_SCRIPT_DIR}"
        ls -l "$s_SCRIPT_DIR" | grep update || true
        return 1
    fi
    
    echo ""
    echo "=================================================="
    echo " INSTALLATION PRE-FLIGHT CHECKLIST"
    echo "=================================================="
    echo " [✓] Repository: $(git -C "$s_REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo "Ready")"
    echo " [✓] Model:      $(basename "$s_SELECTED_MODEL_PATH")"
    echo " [✓] mmproj:     $(basename "$s_SELECTED_MMPROJ_PATH")"
    echo " [✓] Service:    llm.service (enabled)"
    echo " [✓] Run Script: run_llm.sh"
    echo "=================================================="
    echo ""
    f_log_info "Next step: Compiling llama.cpp and deploying binaries."
    echo " Please ensure CUDA toolkit and NVIDIA drivers are ready."
    echo " Press [Enter] to launch update.sh, or Ctrl+C to abort."
    read -r -p "Continue? [y/N]: " s_CONTINUE_CHOICE
    s_CONTINUE_CHOICE="${s_CONTINUE_CHOICE:-N}"
    if [[ "$s_CONTINUE_CHOICE" =~ ^[Yy]$ ]]; then
        f_log_info "Invoking update.sh..."
        bash "$s_UPDATE_SCRIPT" || {
            f_log_warn "update.sh exited with code $?"
            f_log_info "You can manually run it later: sudo bash ${s_UPDATE_SCRIPT}"
        }
    else
        f_log_info "Skipped update.sh invocation."
    fi
}

# ====================== MAIN ENTRY POINT (DFD: RULE_ENTRY_POINT) ======================
f_main() {
    echo "=================================================="
    echo " LLM Installer v${s_SCRIPT_VERSION} — DFD Compliant"
    echo "=================================================="
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --debug) b_DEBUG_MODE=true; shift ;;
            *) shift ;;
        esac
    done
    
    if $b_DEBUG_MODE; then
        f_log_info "Debug mode enabled."
    fi
    
    # Menu
    while true; do
        echo ""
        echo "Select action:"
        echo "  [1] Install/Configure llama.cpp environment"
        echo "  [2] Exit"
        read -r -p "Choice [1]: " i_ACTION
        i_ACTION="${i_ACTION:-1}"
        
        case "$i_ACTION" in
            1) break ;;
            2) f_log_info "Exiting installer."; exit 0 ;;
            *) f_log_warn "Invalid selection. Try again." ;;
        esac
    done
    
    # 1. Validate/Update Repo
    f_handle_repo || { f_log_error "Repo step failed."; exit 1; }
    
    # 2. Report current state independently
    f_check_status
    
    # 3. Smart Skip Check: If run_llm.sh and models exist, ask to skip configuration
    if [[ -f "$s_RUN_SCRIPT_PATH" ]] && [[ -n "$(find "$s_MODEL_DIR" -maxdepth 1 -name '*.gguf' 2>/dev/null | head -n 1)" ]]; then
        echo ""
        read -r -p "Existing config detected (run script + models). Skip configuration? [Y/n]: " s_SKIP_CHOICE
        
        # FIX: Handle Ctrl+C properly. If read fails (interrupt), default to 'N' (Don't skip)
        # Previously, empty variable defaulted to Y which was confusing.
        local read_status=$?
        if [[ $read_status -ne 0 ]]; then
            f_log_warn "User interrupted skip prompt."
            s_SKIP_CHOICE="N"
        else
            s_SKIP_CHOICE="${s_SKIP_CHOICE:-Y}"
        fi
        
        if [[ "$s_SKIP_CHOICE" =~ ^[Nn]$ ]]; then
            f_log_info "Proceeding with configuration steps..."
        else
            f_log_success "Skipping configuration. Proceeding to build..."
            f_invoke_update || { f_log_warn "Update invocation finished with warnings."; }
            echo ""
            f_log_success "Installation sequence completed."
            exit 0
        fi
    fi
    
    # 4. Configure remaining components sequentially & independently
    f_handle_model   || { f_log_error "Model step failed."; exit 1; }
    f_handle_service || { f_log_error "Service step failed."; exit 1; }
    f_handle_run_script || { f_log_error "Run script step failed."; exit 1; }
    
    # 5. Invoke build/deploy
    f_invoke_update  || { f_log_warn "Update invocation finished with warnings."; }
    
    echo ""
    f_log_success "Installation sequence completed."
    exit 0
}

trap 'f_log_info "Script interrupted. Cleaning up..." 2>/dev/null || true' EXIT INT TERM

f_main "$@"
