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
  - supported systems without NVIDIA `P102-100`
  - generic CUDA-capable systems

- **Flexible Build Targeting**
  Supports building:
  - latest `master`
  - a historical version by date
  - any specific commit SHA
  - rebuild current version
  - build separate binaries for each GPU architecture + Universal binary
   
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
    LLM Update Script v6.2 — DFD Compliant
    Repo: /opt/llm/llama.cpp
==================================================
[INFO]  00:18:51 - Loaded service config: llm-server.service

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
| Node.js          | v24.16.0     | OK     |
| npm              | 11.13.0      | OK     |
| NCCL (multi-GPU) | OK           | OK     |
+------------------+--------------+--------+
[INFO]  00:18:51 - Checking build tools...
[OK]    00:18:51 - ✓ All build tools are installed
[INFO]  00:18:51 - Detecting NVIDIA GPUs...
[OK]    00:18:51 - ✓ Detected 6 GPU(s). Unique Architectures: 61;89
[INFO]  00:18:52 - Service llm-server.service is currently ACTIVE
[OK]    00:18:52 - ✓ Service name saved: llm-server.service

Select action:
  [1] Update / Build
  [2] Rollback to previous build
  [3] Exit
Selection: 1

=== STEP: Updating llama.cpp ===

[INFO]  00:20:50 - Stopping service llm-server.service...
[WARN]  00:21:01 - ⚠️  A backup for commit 4988f6e8 already exists:
[WARN]  00:21:01 - ⚠️    backup_2026-06-14_09-30-26_4988f6e8_2026-06-13_10-49-00-0700
Create another backup for this commit? [y/N] n
[INFO]  00:21:24 - Skipping backup creation as requested.

Select version to build:
  [1] Latest (master)
  [2] By date (YYYY-MM-DD)
  [3] By commit
  [4] Rebuild current version (4988f6e8)
  [5] Exit
Choice [1]: 1
[INFO]  00:23:31 - Pulling latest version...
remote: Enumerating objects: 143, done.
remote: Counting objects: 100% (70/70), done.
remote: Compressing objects: 100% (17/17), done.
remote: Total 23 (delta 17), reused 12 (delta 6), pack-reused 0 (from 0)
Распаковка объектов: 100% (23/23), 5.56 КиБ | 355.00 КиБ/с, готово.
Из https://github.com/ggerganov/llama.cpp
   4988f6e8..6e14286e  master     -> origin/master
 * [новая метка]       b9631      -> b9631
 * [новая метка]       b9627      -> b9627
 * [новая метка]       b9628      -> b9628
 * [новая метка]       b9630      -> b9630
Указатель HEAD сейчас на коммите 6e14286e cli : fix not copying preserved tokens (#24258)
Уже актуально.
[OK]    00:23:34 - ✓ Latest master/main checked out
[INFO]  00:23:34 - Determining optimal build strategy based on CPU capabilities...

Processor: Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz
Cores: 56
CPU Capabilities detected:
   AVX2          : true
   AVX512        : false
   AVX512_VBMI   : false
   AVX512_VNNI   : false
   AVX512_BF16   : false
   F16C          : false

[INFO]  00:23:34 - AVX2-capable CPU detected → GGML_NATIVE=ON
Use this configuration? [Y/n] y
[INFO]  00:24:25 - Final decision: GGML_NATIVE=ON

Multiple GPU architectures detected: 61;89
Please select build strategy:
  [1] Single binary with all architectures (Default)
  [2] Separate binaries for each architecture + Universal binary
Choice [1]: 2
[INFO]  00:24:49 - Multi-architecture build mode enabled.
[INFO]  00:24:49 - Starting build...
[INFO]  00:24:49 - Using nvcc: /usr/local/cuda-12.8/bin/nvcc
[INFO]  00:24:49 - Building with architectures: 61;89

...
...
...

==================================================
MULTI-ARCHITECTURE BUILD SUMMARY
==================================================
Universal binary (all archs) deployed:
From /opt/llm/llama.cpp/build/bin/llama-server to /opt/llm/llama-server
To deploy specific architecture binaries, use the following commands:
  cp /opt/llm/llama.cpp/build_61/bin/llama-server-61 /opt/llm
  cp /opt/llm/llama.cpp/build_89/bin/llama-server-89 /opt/llm
==================================================
[OK]    00:34:54 - ✓ Build completed successfully
[INFO]  00:34:54 - Starting deployment...
[INFO]  00:34:55 - Deploying binaries from /opt/llm/llama.cpp/build/bin to /opt/llm
[INFO]  00:34:55 - Skipped copy: llama-server is a valid symlink to build dir
[OK]    00:34:55 - ✓ Binaries deployed to /opt/llm (3 files)
[INFO]  00:34:55 - Verifying deployed binaries...
[OK]    00:34:55 - ✓ Binary verification passed (--version)
[INFO]  00:34:55 - Build record saved to /opt/llm/backup/build_history.log
[INFO]  00:34:55 - Starting service llm.service...
[OK]    00:34:59 - ✓ Service started successfully
[INFO]  00:34:59 - Displaying service status...

=== SERVICE STATUS: llm.service ===

● llm.service - LLM Inference Server
     Loaded: loaded (/etc/systemd/system/llm.service; enabled; preset: enabled)
     Active: active (running) since Mon 2026-06-15 00:34:56 +12; 3s ago
   Main PID: 729540 (run_llm.sh)
      Tasks: 61 (limit: 629145)
     Memory: 144.4M (peak: 153.0M)
        CPU: 2.943s
     CGroup: /system.slice/llm.service
             ├─729540 /bin/bash /opt/llm/run_llm.sh
             └─729541 /opt/llm/llama-server -m /mnt/Models/...
        systemd[1]: Started llm.service - LLM Inference Server.
[OK]    00:34:59 - ✓ Operation completed successfully
```

## Example build_history.log
```text
==================================================
Build Record: 2026-06-15 00:34:55
==================================================
Commit: 6e14286e
Commit Date: 2026-06-14 11:52:15 +0200
--------------------------------------------------
System Information:
  GPUs: NVIDIA P102-100 NVIDIA GeForce RTX 4090
  Driver: 570.211.01
  CUDA Toolkit: 12.8
--------------------------------------------------
Full Compilation Flags:
  CMake flags: -DCMAKE_CUDA_COMPILER=/usr/local/cuda-12.8/bin/nvcc         -DCMAKE_CUDA_ARCHITECTURES=61;89         -DGGML_CUDA=ON         -DGGML_CURL=ON         -DGGML_CUDA_FA_ALL_QUANTS=ON         -DGGML_NATIVE=ON         -DCMAKE_CUDA_FLAGS=-Wno-deprecated-gpu-targets         -DCMAKE_BUILD_TYPE=Release -DGGML_AVX2=ON -DGGML_F16C=ON
  Make flags: -j56 --target llama-cli llama-server llama-gguf-split
```
