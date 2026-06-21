#!/usr/bin/env bash
# =============================================================================
# Git Delta Report Generator — DFD Compliant Edition (v1.0.17 - Log Fix & Hash Defense)
# Purpose: Generate chunked delta reports between two git commits with file filtering.
# DFD Compliance: [RULE_MANDATORY_COMPLIANCE], [RULE_CONFIG_EXEC_SEPARATION],
#                 [RULE_ERROR_HANDLING], [RULE_NO_UNHANDLED_EXCEPTIONS],
#                 [RULE_CONTROLLED_LOOPS], [RULE_IDEMPOTENCY], [RULE_ENGLISH_OUTPUT],
#                 [RULE_LOG_FORMAT], [RULE_DEBUG], [RULE_HELP_OUTPUT], [RULE_VERSION_OUTPUT],
#                 [RULE_SELF_REVIEW], [RULE_DEFENSE]
# =============================================================================

# <PLAN>
# 1. Parse CLI args (path, start/end refs, chunk size, etc.).
# 2. Validate environment (git repo exists, refs are valid, short hashes verified).
# 3. Fetch remote updates to ensure latest state.
# 4. Resolve refs and get commit list using 'git log' (stdout for data, stderr for logs).
# 5. Chunk commits and generate reports with diffs.
# 6. Handle signals (INT/TERM) for clean exit.
# Risks: 
#   - Subshell stdout/stderr mixing (fixed by explicit redirections).
#   - Short hash collisions (mitigated by length check).
#   - Large diff output slowing down generation.
# Mitigation:
#   - Explicit ref verification.
#   - || true guards for network commands.
#   - Tee to file to capture output without blocking excessively.
# DFD Alignment: Config separation, English logs, debug mode, idempotent output.
# </PLAN>

set -uo pipefail
export LC_ALL=C.UTF-8

# ========================
# [RULE_CONFIG_EXEC_SEPARATION] Configuration Block
# ========================
readonly SCRIPT_NAME="$(basename "$0")"
# [RULE_VERSION_OUTPUT] Version constant
readonly SCRIPT_VERSION="1.0.17"
readonly SCRIPT_DATE="2024-05-20"
readonly DEFAULT_CHUNK_SIZE=20
readonly DEFAULT_START_REF="HEAD"
readonly DEFAULT_END_REF="origin/main"
readonly DEFAULT_OUTPUT_DIR="./reports"
readonly DEFAULT_INCLUDE_EXTS=".md .txt .py .cpp .h .c .js .ts .jsx .tsx .css .html .json .yaml .yml .sh"
readonly LOG_PREFIX="DFD_GitDelta"

# Runtime state (mutable)
DEBUG_MODE=false
REPO_PATH=""
REMOTE_URL=""
START_REF="$DEFAULT_START_REF"
END_REF="$DEFAULT_END_REF"
CHUNK_SIZE="$DEFAULT_CHUNK_SIZE"
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
INCLUDE_EXTS="$DEFAULT_INCLUDE_EXTS"

# [DFD: RULE_DEFENSE] Explicit initialization to prevent 'unbound variable' with set -u
TOTAL_COMMITS=0
TOTAL_INS=0
TOTAL_DEL=0
TOTAL_FILES_CHANGED=0

# ========================
# [RULE_LOG_FORMAT] Logging Functions
# ========================
# Logs go to stderr by default to prevent mixing with data captured via $()
log_info()  { printf "[INFO] %s: %s\n" "$LOG_PREFIX" "$*" >&2; }
log_warn()  { printf "[WARN] %s: %s\n" "$LOG_PREFIX" "$*" >&2; }
log_error() { printf "[ERROR] %s: %s\n" "$LOG_PREFIX" "$*" >&2; }
log_debug() { [[ "$DEBUG_MODE" == true ]] && printf "[DEBUG] %s: %s\n" "$LOG_PREFIX" "$*" >&2 || true; }

# ========================
# [RULE_HELP_OUTPUT] & [RULE_VERSION_OUTPUT]
# ========================
show_version() { 
    # [RULE_VERSION_OUTPUT] Display version on startup or request
    printf "%s %s (%s)\n" "$SCRIPT_NAME" "$SCRIPT_VERSION" "$SCRIPT_DATE"
}

show_help() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Required:
  --path PATH       Path to the local git repository

Optional:
  --start REF       Start reference (default: HEAD)
  --end REF         End reference (default: origin/main)
  --chunk NUM       Commits per report file (default: 20)
  --remote URL      Remote URL (updates/sets origin)
  --output DIR      Output directory (default: ./reports)
  --ext EXT_LIST    Space-separated file extensions to include in diffs (default: built-in list)
  --debug           Enable debug logging
  --version         Show version
  --help            Show this help

Examples:
  $SCRIPT_NAME --path /opt/llm/llama.cpp --start 63e66fdd --end 94a220cd --chunk 15 --output ./delta
EOF
    exit 0
}

# ========================
# [RULE_PROACTIVE] Signal Handling & Cleanup
# ========================
trap 'log_error "Interrupted by signal. Exiting."; exit 130' INT TERM

# ========================
# [RULE_CONFIG_FLEXIBILITY] CLI & Env Parsing
# ========================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --start)   START_REF="$2"; shift 2 ;;
            --end)     END_REF="$2"; shift 2 ;;
            --chunk)   CHUNK_SIZE="$2"; shift 2 ;;
            --path)    REPO_PATH="$2"; shift 2 ;;
            --remote)  REMOTE_URL="$2"; shift 2 ;;
            --output)  OUTPUT_DIR="$2"; shift 2 ;;
            --ext)     INCLUDE_EXTS="$2"; shift 2 ;;
            --debug)   DEBUG_MODE=true; shift ;;
            --version) show_version; exit 0 ;;
            --help)    show_help ;;
            *) log_error "Unknown option: $1"; show_help ;;
        esac
    done
}

# ========================
# [RULE_ERROR_HANDLING] Validation & Setup
# ========================
validate_inputs() {
    if [[ -z "$REPO_PATH" ]]; then
        log_error "Missing required argument: --path"
        exit 1
    fi

    if [[ ! -d "$REPO_PATH" ]]; then
        log_error "Directory not found: $REPO_PATH"
        exit 1
    fi

    cd "$REPO_PATH" || exit 1
    if [[ ! -d ".git" ]]; then
        log_error "Not a git repository (missing .git): $REPO_PATH"
        exit 1
    fi

    # [RULE_DEFENSE] Validate short hash length for reliability
    if [[ ${#START_REF} -lt 10 ]]; then
        log_warn "Short start ref used ($START_REF). Recommend 10+ chars for uniqueness."
    fi
    if [[ ${#END_REF} -lt 10 ]]; then
        log_warn "Short end ref used ($END_REF). Recommend 10+ chars for uniqueness."
    fi

    [[ "$REPO_PATH" != "${REPO_PATH#$(pwd)}" ]] || log_info "Config: --path set to $REPO_PATH"
    [[ "$START_REF" != "$DEFAULT_START_REF" ]] && log_info "Config: --start set to $START_REF"
    [[ "$END_REF" != "$DEFAULT_END_REF" ]] && log_info "Config: --end set to $END_REF"
    [[ "$CHUNK_SIZE" != "$DEFAULT_CHUNK_SIZE" ]] && log_info "Config: --chunk set to $CHUNK_SIZE"
    [[ -n "$REMOTE_URL" ]] && log_info "Config: --remote set to $REMOTE_URL"
    [[ "$OUTPUT_DIR" != "$DEFAULT_OUTPUT_DIR" ]] && log_info "Config: --output set to $OUTPUT_DIR"
    [[ "$DEBUG_MODE" == true ]] && log_info "Config: --debug enabled"

    if ! [[ "$CHUNK_SIZE" =~ ^[1-9][0-9]*$ ]]; then
        log_error "Invalid chunk size: $CHUNK_SIZE. Must be a positive integer."
        exit 1
    fi
}

# ========================
# [RULE_EXTERNAL_INTEGRATION] Git Operations
# ========================
setup_remote() {
    if [[ -n "$REMOTE_URL" ]]; then
        if git remote get-url origin &>/dev/null; then
            git remote set-url origin "$REMOTE_URL"
            log_info "Remote: Updated origin to $REMOTE_URL"
        else
            git remote add origin "$REMOTE_URL"
            log_info "Remote: Added origin as $REMOTE_URL"
        fi
    fi
}

fetch_commits() {
    log_info "Fetching remote updates..."
    # [RULE_EXTERNAL_INTEGRATION] Robust fetch with error handling
    git fetch origin >/dev/null 2>&1 || log_warn "Fetch failed or network unreachable."
    
    local start_resolved end_resolved
    
    # [RULE_DEFENSE] Resolve refs explicitly to ensure they exist
    if ! start_resolved=$(git rev-parse --verify "$START_REF" 2>/dev/null); then
        log_error "Invalid start ref: $START_REF"
        return 1
    fi
    
    if ! end_resolved=$(git rev-parse --verify "$END_REF" 2>/dev/null); then
        log_error "Invalid end ref: $END_REF"
        return 1
    fi
    
    log_debug "Resolved START: $start_resolved"
    log_debug "Resolved END:   $end_resolved"
    
    local test_range="$start_resolved..$end_resolved"
    log_info "Testing git log range: $test_range"
    
    # Capture ONLY git output to stdout. Logs go to stderr.
    local raw_commits=""
    local exit_code=0
    raw_commits=$(git log "$test_range" --pretty=format:"%H|%an|%ad|%s" --date=short 2>&1) || exit_code=$?
    
    log_debug "Git log exit code: $exit_code"
    log_debug "Raw output length: ${#raw_commits} bytes"
    
    if [[ -z "$raw_commits" ]]; then
        log_warn "Git log returned empty for range '$test_range'."
        log_debug "Attempting reverse range check..."
        raw_commits=$(git log "$end_resolved..$start_resolved" --pretty=format:"%H|%an|%ad|%s" --date=short 2>&1) || true
        if [[ -n "$raw_commits" ]]; then
            log_info "Reverse range works. Commits might be in reverse order or history is non-linear."
        else
            log_error "Both ranges failed. Checking refs manually..."
            git log --oneline -n 3 "$start_resolved" 2>/dev/null
            git log --oneline -n 3 "$end_resolved" 2>/dev/null
            return 1
        fi
    fi
    
    # [RULE_DEFENSE] Count commits safely outside subshell scope
    TOTAL_COMMITS=$(echo "$raw_commits" | wc -l | tr -d ' ')
    log_info "Successfully resolved $TOTAL_COMMITS commit(s)."
    
    # Output ONLY commit data to stdout for capture
    echo "$raw_commits"
}

# ========================
# [RULE_DATA_PROCESSING] Filter Logic
# ========================
should_include_file() {
    local file="$1"
    [[ -z "$file" ]] && return 1

    local ext=".${file##*.}"
    if [[ "$INCLUDE_EXTS" == *"$ext"* ]] || [[ -z "$INCLUDE_EXTS" ]]; then
        return 0
    fi
    return 1
}

# ========================
# [RULE_CONTROLLED_LOOPS] Report Generation
# ========================
generate_reports() {
    local raw_commits="$1"
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local project_name
    project_name=$(basename "$(pwd)")

    if ! mkdir -p "$OUTPUT_DIR" 2>/dev/null; then
        log_error "Failed to create output directory: $OUTPUT_DIR"
        exit 1
    fi

    if [[ $TOTAL_COMMITS -eq 0 ]]; then
        log_info "No commits to process. Skipping report generation."
        return 0
    fi

    local num_files=$(( (TOTAL_COMMITS + CHUNK_SIZE - 1) / CHUNK_SIZE ))
    total_ins=0
    total_del=0
    total_files_changed=0

    local i
    for (( i=1; i<=num_files; i++ )); do
        local start_idx=$(( (i - 1) * CHUNK_SIZE + 1 ))
        local end_idx=$(( i * CHUNK_SIZE ))
        [[ $end_idx -gt $TOTAL_COMMITS ]] && end_idx=$TOTAL_COMMITS
        local group_size=$(( end_idx - start_idx + 1 ))

        local suffix=""
        [[ $num_files -gt 1 ]] && suffix="_part${i}_of${num_files}"

        local out_file="${OUTPUT_DIR}/${timestamp}${suffix}.txt"
        log_debug "Processing chunk $i/$num_files: commits $start_idx-$end_idx"

        local -a current_commits
        readarray -t current_commits < <(echo "$raw_commits" | awk "NR>=${start_idx} && NR<=${end_idx}")

        {
            echo "Git Changes Summary — ${project_name}"
            echo "Date: $(date +"%Y-%m-%d %H:%M:%S")"
            echo "Part: ${i}/${num_files} (commits ${start_idx}-${end_idx} of ${TOTAL_COMMITS})"
            echo "Ref: ${START_REF} → ${END_REF}"
            echo "=========================================================================================="
            echo ""
            echo "Commits in this file: ${group_size}"
            echo ""
        } > "$out_file"

        local group_ins=0 group_del=0 group_files=0 idx=0

        for line in "${current_commits[@]}"; do
            [[ -z "$line" ]] && continue
            idx=$((idx + 1))
            local global_num=$(( start_idx + idx - 1 ))

            local commit_hash="${line%%|*}"
            local rest="${line#*|}"
            local author="${rest%%|*}"
            rest="${rest#*|}"
            local date_val="${rest%%|*}"
            local subject="${rest#*|}"

            {
                echo "=========================================================================================="
                echo "Commit ${global_num}/${TOTAL_COMMITS}"
                echo "Hash : ${commit_hash}"
                echo "Author: ${author}"
                echo "Date : ${date_val}"
                echo "Subject : ${subject}"
                echo ""
            } >> "$out_file"

            local files_raw
            files_raw=$(git show --name-only --pretty=format: "$commit_hash" 2>/dev/null) || true
            local file_count=0
            if [[ -n "$files_raw" ]]; then
                while IFS= read -r fl; do
                    [[ -z "$fl" ]] && continue
                    if should_include_file "$fl"; then
                        echo "   • ${fl}" >> "$out_file"
                        file_count=$((file_count + 1))
                        echo "--- DIFF ---" >> "$out_file"
                        # Redirect directly to file, keep console clean
                        git show --no-color "$commit_hash" -- "$fl" >> "$out_file" 2>/dev/null || true
                        echo "" >> "$out_file"
                    fi
                done <<< "$files_raw"
            fi
            echo "Changed files: ${file_count}" >> "$out_file"
            echo "" >> "$out_file"

            local numstat_raw
            numstat_raw=$(git show --numstat --pretty=format: "$commit_hash" 2>/dev/null) || true
            if [[ -n "$numstat_raw" ]]; then
                while IFS=$'\t' read -r ins del _file; do
                    [[ -z "$ins" ]] && continue
                    local i_val="${ins}" d_val="${del}"
                    [[ "$i_val" == "-" ]] && i_val=0
                    [[ "$d_val" == "-" ]] && d_val=0
                    group_ins=$((group_ins + i_val))
                    group_del=$((group_del + d_val))
                    group_files=$((group_files + 1))
                done <<< "$numstat_raw"
            fi
        done

        {
            echo "=========================================================================================="
            echo "SUMMARY FOR GROUP ${i}/${num_files}"
            echo "=========================================================================================="
            echo "Commits in group: ${group_size}"
            echo "Files changed:    ${group_files}"
            echo "Lines added:      ${group_ins}"
            echo "Lines deleted:    ${group_del}"
            echo "Net growth:       $((group_ins - group_del)) lines"
            echo ""
        } >> "$out_file"

        total_ins=$((total_ins + group_ins))
        total_del=$((total_del + group_del))
        total_files_changed=$((total_files_changed + group_files))
        log_info "Generated: $(basename "$out_file") (${group_size} commits)"
    done

    log_info "✅ Completed. Created ${num_files} file(s)."
    log_info "   Total net growth: +$((total_ins - total_del)) lines"
    
    # Print absolute path to the output directory
    local abs_output_dir
    abs_output_dir=$(realpath "$OUTPUT_DIR")
    log_info "   Delta saved to: $abs_output_dir"
}

# ========================
# [RULE_ENTRY_POINT] Main Execution
# ========================
main() {
    # [RULE_VERSION_OUTPUT] Display version at startup
    show_version
    
    parse_args "$@"
    validate_inputs
    setup_remote
    
    # Capture ONLY git data from fetch_commits (logs go to stderr)
    local raw_commits
    raw_commits=$(fetch_commits) || { 
        log_info "Fetch command returned non-zero (likely no commits). Exiting."
        exit 0 
    }
    
    if [[ -z "$raw_commits" ]]; then
        log_info "No commits to process. Exiting gracefully."
        exit 0
    fi
    
    # Calculate total outside subshell
    TOTAL_COMMITS=$(echo "$raw_commits" | wc -l | tr -d ' ')
    log_info "Total commits to process: $TOTAL_COMMITS"
    
    generate_reports "$raw_commits"
}

main "$@"
