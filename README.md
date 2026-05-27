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
    LLM Update Script v5.3 — DFD Compliant
    Repo: /opt/llm/llama.cpp
==================================================
[INFO]  17:46:25 - Loaded service config: llm.service

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
| Node.js          | v24.15.0     | OK     |
| npm              | 11.12.1      | OK     |
| NCCL (multi-GPU) | OK           | OK     |
+------------------+--------------+--------+
[INFO]  17:46:27 - Checking build tools...
[OK]    17:46:28 - ✓ All build tools are installed
[INFO]  17:46:28 - Detecting NVIDIA GPUs...
[OK]    17:46:28 - ✓ Detected 6 GPU(s). Architectures: 61;61;61;61;61;61
[WARN]  17:46:28 - ⚠️  Pascal detected → GGML_NATIVE=OFF
[INFO]  17:46:29 - Service llm.service is currently ACTIVE
[OK]    17:46:29 - ✓ Service name saved: llm.service

Select action:
  [1] Update / Build
  [2] Rollback to previous build
  [3] Exit
Selection: 1

=== STEP: Updating llama.cpp ===

[INFO]  17:46:38 - Stopping service llm.service...
[INFO]  17:48:09 - Creating backup → /opt/llm/backup/backup_20260527_174809
[OK]    17:49:40 - ✓ Backup created: backup_20260527_174809

Select version to build:
  [1] Latest (master)
  [2] By date (YYYY-MM-DD)
  [3] By commit
Choice [1]: 1
[INFO]  17:58:47 - Pulling latest version...
remote: Enumerating objects: 370, done.
remote: Counting objects: 100% (126/126), done.
remote: Compressing objects: 100% (32/32), done.
remote: Total 50 (delta 42), reused 25 (delta 18), pack-reused 0 (from 0)
Unpacking objects: 100% (50/50), 23.61 KiB | 241.00 KiB/s, done.
From https://github.com/ggerganov/llama.cpp
   837bb6b4..aa50b2c2  master     -> origin/master
 * [new tag]           b9365      -> b9365
 * [new tag]           b9366      -> b9366
 * [new tag]           b9367      -> b9367
 
....

[100%] Linking CXX executable ../../bin/llama-server
[100%] Built target llama-server
[  0%] Built target llama-common-base
[  0%] Built target cpp-httplib
[  3%] Built target ggml-base
[  7%] Built target ggml-cpu
[ 52%] Built target ggml-cuda
[ 52%] Built target ggml
[ 91%] Built target llama
[100%] Built target llama-common
[100%] Building CXX object tools/gguf-split/CMakeFiles/llama-gguf-split.dir/gguf-split.cpp.o
[100%] Linking CXX executable ../../bin/llama-gguf-split
[100%] Built target llama-gguf-split
[OK]    18:09:28 - ✓ Build completed successfully
[INFO]  18:09:28 - Starting deployment...
[INFO]  18:09:28 - Deploying binaries from /opt/llm/llama.cpp/build/bin to /opt/llm
[OK]    18:09:28 - ✓ Binaries deployed to /opt/llm (3 files)
[INFO]  18:09:28 - Verifying deployed binaries...
[OK]    18:09:34 - ✓ Binary verification passed (--version)
[INFO]  18:09:35 - Build record saved to /opt/llm/backup/build_history.log
[INFO]  18:09:35 - Starting service llm.service...
[OK]    18:09:38 - ✓ Service started successfully
[INFO]  18:09:38 - Displaying service status...

=== SERVICE STATUS: llm.service ===

● llm.service - Local LLM Service
     Loaded: loaded (/etc/systemd/system/llm.service; enabled; preset: enabled)
     Active: active (running) since Wed 2026-05-27 18:09:35 UTC; 3s ago
   Main PID: 922022 (bash)
      Tasks: 24 (limit: 37997)
     Memory: 382.8M (peak: 387.1M)
        CPU: 1.640s
     CGroup: /system.slice/llm.service
             ├─922022 /bin/bash /opt/llm/run_llm.sh
             └─922024 /opt/llm/llama-server -m 
			 ...
			 
[OK]    18:09:38 - ✓ Operation completed successfully


