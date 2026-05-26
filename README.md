## Full Automation for `llama.cpp`

Full automation of `llama.cpp` update, backup, rollback, and system recovery for Pascal (`P102-100`) and mixed GPU configurations.

---

## Script Features

- **Updates `llama.cpp`**
  Designed specifically with requirements matching NVIDIA `P102-100` / Pascal GPUs in mind.

- **Compatibility Check & Driver Installation**
  Verifies required NVIDIA Driver and CUDA Toolkit versions.
  Automatically installs or updates missing/incompatible components.

- **Dependency Management**
  Installs all required packages and build dependencies for:
  - compiling `llama.cpp`
  - running inference
  - launching the web interface

- **Mixed GPU Configuration Support**
  Works with:
  - mixed GPU environments
  - systems without NVIDIA `P102-100`
  - generic CUDA-capable systems

- **Flexible Build Targeting**
  Supports building:
  - latest `master`
  - a historical version by date
  - any specific commit SHA

- **Automatic Rollback**
  Restores the last working build automatically if compilation or deployment fails.

---
### Key Paths
```
| Path                              | Purpose                            |
|-----------------------------------|------------------------------------|
| /opt/llm/llama.cpp                | Source code repository (git clone) |
| /opt/llm/backup                   | Backup snapshots with timestamps   |
| /opt/llm/backup/build_history.log | Build records log                  |
| /opt/llm/.service_config          | Service name configuration         |
| /opt/llm/llama-*                  | Deployed binaries                  |
```

## Step 1 - edit script configuration
```bash
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
```

## Step 2 - run
```bash
$ sudo bash /home/user/AI_script/llama.cpp.update/update.sh
```

## Example Console Output



```text
==================================================
    LLM Update Script v4.7 — DFD Compliant
    Repo: /opt/llm/llama.cpp
==================================================
[INFO]  14:52:37 - Loaded service config: llm.service

=== NVIDIA P102-100 Compatibility Checklist ===
+---------------+------------+--------+
| Component     | Version    | Status |
+---------------+------------+--------+
| NVIDIA Driver | 570.211.01 | OK     |
| CUDA Toolkit  | 12.8       | OK     |
+---------------+------------+--------+

=== System Requirements ===
+------------------+--------------+--------+
| Component        | Version      | Status |
+------------------+--------------+--------+
| OS               | Ubuntu 24.04 | OK     |
| Node.js          | v20.20.2     | OK     |
| npm              | 10.8.2       | OK     |
| NCCL (multi-GPU) | OK           | OK     |
+------------------+--------------+--------+
[INFO]  14:52:38 - Detecting NVIDIA GPUs...
[OK]    14:52:38 - ✓ Detected 1 GPU(s). Architectures: 61
[WARN]  14:52:38 - ⚠️  Pascal detected → GGML_NATIVE=OFF
[INFO]  14:52:39 - Service llm.service is currently ACTIVE
[OK]    14:52:39 - ✓ Service name saved: llm.service

Select action:
  [1] Update / Build
  [2] Rollback to previous build
  [3] Exit
Selection: 1

=== STEP: Updating llama.cpp ===

[INFO]  14:52:43 - Stopping service llm.service...
[INFO]  14:52:44 - Creating backup → /opt/llm/backup/backup_20260526_145244
[OK]    14:53:00 - ✓ Backup created: backup_20260526_145244

Select version to build:
  [1] Latest (master)
  [2] By date (YYYY-MM-DD)
  [3] By commit
Choice [1]: 1
[INFO]  14:53:05 - Pulling latest version...
remote: Enumerating objects: 1938, done.
remote: Counting objects: 100% (663/663), done.
remote: Compressing objects: 100% (234/234), done.
Receiving objects: 100% (352/352), 124.68 KiB | 8.91 MiB/s, done.
remote: Total 352 (delta 285), reused 170 (delta 113), pack-reused 0 (from 0)
Resolving deltas: 100% (285/285), completed with 150 local objects.
From https://github.com/ggerganov/llama.cpp
   549b9d84..5190c2ea  master     -> origin/master
 * [new tag]           b9309      -> b9309
 * [new tag]           b9310      -> b9310
 * [new tag]           b9311      -> b9311
 
....

[100%] Built target llama-server
[  0%] Built target cpp-httplib
[  3%] Built target ggml-base
[  3%] Built target llama-common-base
[  7%] Built target ggml-cpu
[ 52%] Built target ggml-cuda
[ 52%] Built target ggml
[ 91%] Built target llama
[100%] Built target llama-common
[100%] Building CXX object tools/gguf-split/CMakeFiles/llama-gguf-split.dir/gguf-split.cpp.o
[100%] Linking CXX executable ../../bin/llama-gguf-split
[100%] Built target llama-gguf-split
[OK]    15:16:07 - ✓ Build completed successfully
[INFO]  15:16:07 - Deploying binaries from /opt/llm/llama.cpp/build/bin to /opt/llm
[OK]    15:16:07 - ✓ Binaries deployed to /opt/llm
[INFO]  15:16:07 - Verifying deployed binaries...
[OK]    15:16:09 - ✓ Binary verification passed (--version)
[INFO]  15:16:09 - Build record saved to /opt/llm/backup/build_history.log
[INFO]  15:16:09 - Starting service llm.service...
[OK]    15:16:12 - ✓ Service started successfully
[OK]    15:16:12 - ✓ Operation completed successfully


