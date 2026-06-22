## Full Automation for `llama.cpp`

Full automation of `llama.cpp` update, backup, rollback, and system recovery for Pascal (`P102-100`) and mixed GPU configurations.

---

## Script Features

### Core Functionality
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
  - Latest `master`
  - A historical version by date
  - Any specific commit SHA
  - Rebuild current version (skip git checkout)
  - Redeploy current version (skip git + build)
  - Separate binaries for each GPU architecture + Universal binary (multi-arch mode)
   
- **Automatic Rollback**
  Restores the last working build automatically if compilation or deployment fails.
- **Delta Report Generation** — Generates detailed commit comparison reports between pre/post sync states using `git_delta.sh`
- **Smart Build Strategy** — CPU-based optimization selection (AVX512/AVX2/F16C) with interactive override
- **Symlink-Aware Deployment** — Idempotent copy skip for symlinks pointing to build directory
- **Commit-Aware Backup Naming** — Backup names include commit hash and commit date with duplicate detection
- **Clean Build Log Format** — Structured build history with full compilation flags, system info, and commit metadata
- **Recursive Deploy Retry** — Interactive retry mechanism with detailed diagnostics for deployment failures
- **Already Up-to-Date Check** — Detects when local version matches remote and offers skip option
- **Install.sh Integration** — Automatic `llama.cpp` installation if missing: clone repository, create service, download llm-model.

---
### Key Paths
```
| Path                              | Purpose                              |
|-----------------------------------|--------------------------------------|
| /opt/llm/llama.cpp                | Source code repository (git clone)   |
| /opt/llm/backup                   | Backup snapshots with timestamps     |
| /opt/llm/backup/build_history.log | Build records log                    |
| /opt/llm/.service_config          | Service name configuration           |
| /opt/llm/llama-*                  | Deployed binaries                    |
| `/opt/llm/llama.cpp/reports/`     | Delta report output directory (diff) |
```

---

## Step 1 - edit script configuration
```bash
readonly SCRIPT_BASENAME="/opt/llm"
readonly REPO_DIR="${SCRIPT_BASENAME}/llama.cpp"
readonly BACKUP_DIR="${SCRIPT_BASENAME}/backup"
readonly SERVICE_CONFIG="${SCRIPT_BASENAME}/.service_config"
readonly BUILD_HISTORY="${BACKUP_DIR}/build_history.log"
readonly LOCK_FILE="/var/run/llm-update.lock"

# === Delta Report Configuration (DFD: RULE_CONFIG_EXEC_SEPARATION) ===
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DELTA_SCRIPT="${SCRIPT_DIR}/git_delta.sh"
readonly REPORTS_DIR="${REPO_DIR}/reports"

# === Install Script Configuration (New) ===
readonly INSTALL_SCRIPT="${SCRIPT_DIR}/install.sh"

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
    LLM Update Script v6.10 — DFD Compliant
    Repo: /opt/llm/llama.cpp
==================================================
[INFO]  22:55:24 - Loaded service config: llm-server.service

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
| llama.cpp        | 0ef6f06d     | OK     |
| Node.js          | v24.16.0     | OK     |
| npm              | 11.13.0      | OK     |
| NCCL (multi-GPU) | OK           | OK     |
+------------------+--------------+--------+
[INFO]  22:55:24 - Checking build tools...
[OK]    22:55:24 - ✓ All build tools are installed
[INFO]  22:55:24 - Detecting NVIDIA GPUs...
[OK]    22:55:24 - ✓ Detected 6 GPU(s). Unique Architectures: 61;89
[INFO]  22:55:25 - Service llm-server.service is currently ACTIVE
[OK]    22:55:25 - ✓ Service name saved: llm-server.service

Select action:
  [1] Update / Build / Deploy
  [2] Rollback to previous build
  [3] Exit
Selection: 1

=== STEP: Updating llama.cpp ===

[INFO]  22:55:28 - Stopping service llm-server.service...
[INFO]  22:55:29 - Creating backup → /opt/llm/backup/backup_2026-06-22_22-55-29_0ef6f06d_2026-06-22_09-18-31+0530
[OK]    22:55:41 - ✓ Backup created: backup_2026-06-22_22-55-29_0ef6f06d_2026-06-22_09-18-31+0530

Select version to build or redeploy:
  [1] Latest (master)
  [2] By date (YYYY-MM-DD)
  [3] By commit
  [4] Rebuild current version (0ef6f06d)
  [5] Redeploy current version (0ef6f06d)
  [6] Exit
Choice [1]: 1
[INFO]  22:55:45 - Pulling latest version...
remote: Enumerating objects: 45, done.
remote: Counting objects: 100% (35/35), done.
remote: Compressing objects: 100% (4/4), done.
remote: Total 5 (delta 4), reused 2 (delta 1), pack-reused 0 (from 0)
Распаковка объектов: 100% (5/5), 1.60 КиБ | 546.00 КиБ/с, готово.
Из https://github.com/ggerganov/llama.cpp
   0ef6f06d..d0f9d2e5  master     -> origin/master
 * [новая метка]       b9755      -> b9755
 * [новая метка]       b9756      -> b9756
[INFO]  22:55:48 - Local commit:  0ef6f06d553b160d8fc1fba38f5848c7940873a2
[INFO]  22:55:48 - Remote commit: d0f9d2e5ac5d4f51763755958b8f353fed01aaa2 (origin/master)
[OK]    22:55:49 - ✓ Latest origin/master checked out

Generate delta report between 0ef6f06d553b160d8fc1fba38f5848c7940873a2 and d0f9d2e5ac5d4f51763755958b8f353fed01aaa2? [y/N] y
Commits per chunk (default 20): 
[INFO]  22:55:55 - Running delta generator...
git_delta.sh 1.0.17 (2024-05-20)
[INFO] DFD_GitDelta: Config: --start set to 0ef6f06d553b160d8fc1fba38f5848c7940873a2
[INFO] DFD_GitDelta: Config: --end set to d0f9d2e5ac5d4f51763755958b8f353fed01aaa2
[INFO] DFD_GitDelta: Config: --remote set to https://github.com/ggerganov/llama.cpp
[INFO] DFD_GitDelta: Remote: Updated origin to https://github.com/ggerganov/llama.cpp
[INFO] DFD_GitDelta: Fetching remote updates...
[INFO] DFD_GitDelta: Testing git log range: 0ef6f06d553b160d8fc1fba38f5848c7940873a2..d0f9d2e5ac5d4f51763755958b8f353fed01aaa2
[INFO] DFD_GitDelta: Successfully resolved 1 commit(s).
[INFO] DFD_GitDelta: Total commits to process: 1
[INFO] DFD_GitDelta: Generated: 20260622_225556.txt (1 commits)
[INFO] DFD_GitDelta: ✅ Completed. Created 1 file(s).
[INFO] DFD_GitDelta:    Total net growth: +4 lines
[INFO] DFD_GitDelta:    Delta saved to: /opt/llm/llama.cpp/reports
[OK]    22:55:56 - ✓ Delta report generation completed.
[INFO]  22:55:56 - Determining optimal build strategy based on CPU capabilities...

Processor: Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz
Cores: 56
CPU Capabilities detected:
   AVX2          : true
   AVX512        : false
   AVX512_VBMI   : false
   AVX512_VNNI   : false
   AVX512_BF16   : false
   F16C          : false

[INFO]  22:55:56 - AVX2-capable CPU detected → GGML_NATIVE=ON
Use this configuration? [Y/n] y
[INFO]  22:56:00 - Final decision: GGML_NATIVE=ON

Multiple GPU architectures detected: 61;89
Please select build strategy:
  [1] Single binary with all architectures (Default)
  [2] Separate binaries for each architecture + Universal binary
Choice [1]: 2
[INFO]  22:56:07 - Multi-architecture build mode enabled.
[INFO]  22:56:07 - Starting build...
[INFO]  22:56:08 - Using nvcc: /usr/local/cuda-12.8/bin/nvcc
[INFO]  22:56:08 - Building with architectures: 61;89
[INFO]  22:56:08 - Build strategy: (GGML_NATIVE=ON)
[INFO]  22:56:08 - Starting primary compilation...
[INFO]  22:56:08 - Build timestamp: 2026-06-22 22:56:08
[INFO]  22:56:08 - Commit: d0f9d2e5 (2026-06-22 10:55:28 +0200)
[INFO]  22:56:08 - CMake flags: -DCMAKE_CUDA_COMPILER=/usr/local/cuda-12.8/bin/nvcc         -DCMAKE_CUDA_ARCHITECTURES=61;89         -DGGML_CUDA=ON         -DGGML_CURL=ON         -DGGML_CUDA_FA_ALL_QUANTS=ON         -DGGML_NATIVE=ON         -DCMAKE_CUDA_FLAGS=-Wno-deprecated-gpu-targets         -DCMAKE_BUILD_TYPE=Release -DGGML_AVX2=ON -DGGML_F16C=ON
[INFO]  22:56:08 - Make flags: -j56 --target llama-cli llama-server llama-gguf-split
-- The C compiler identification is GNU 13.3.0
-- The CXX compiler identification is GNU 13.3.0
-- Detecting C compiler ABI info
-- Detecting C compiler ABI info - done
-- Check for working C compiler: /usr/bin/cc - skipped
-- Detecting C compile features
-- Detecting C compile features - done
-- Detecting CXX compiler ABI info
-- Detecting CXX compiler ABI info - done
-- Check for working CXX compiler: /usr/bin/c++ - skipped
-- Detecting CXX compile features
-- Detecting CXX compile features - done
CMAKE_BUILD_TYPE=Release
-- Found Git: /usr/bin/git (found version "2.43.0") 
-- The ASM compiler identification is GNU
-- Found assembler: /usr/bin/cc
-- Performing Test CMAKE_HAVE_LIBC_PTHREAD
-- Performing Test CMAKE_HAVE_LIBC_PTHREAD - Success
-- Found Threads: TRUE  
-- Warning: ccache not found - consider installing it for faster compilation or disable this warning with GGML_CCACHE=OFF
-- CMAKE_SYSTEM_PROCESSOR: x86_64
-- GGML_SYSTEM_ARCH: x86
-- Found OpenMP_C: -fopenmp (found version "4.5") 
-- Found OpenMP_CXX: -fopenmp (found version "4.5") 
-- Found OpenMP: TRUE (found version "4.5")  
-- Including CPU backend
-- x86 detected
-- Adding CPU backend variant ggml-cpu: -march=native 
-- Found CUDAToolkit: /usr/local/cuda-12.8/targets/x86_64-linux/include (found version "12.8.93") 
-- CUDA Toolkit found
-- The CUDA compiler identification is NVIDIA 12.8.93
-- Detecting CUDA compiler ABI info
-- Detecting CUDA compiler ABI info - done
-- Check for working CUDA compiler: /usr/local/cuda-12.8/bin/nvcc - skipped
-- Detecting CUDA compile features
-- Detecting CUDA compile features - done
-- Using CMAKE_CUDA_ARCHITECTURES=61;89 CMAKE_CUDA_ARCHITECTURES_NATIVE=89-real;61-real
-- Found NCCL: /usr/lib/x86_64-linux-gnu/libnccl.so  
-- CUDA host compiler is GNU 13.3.0
-- Including CUDA backend
-- ggml version: 0.15.2
-- ggml commit:  d0f9d2e5
-- Found OpenSSL: /usr/lib/x86_64-linux-gnu/libcrypto.so (found version "3.0.13")  
-- Performing Test OPENSSL_VERSION_SUPPORTED
-- Performing Test OPENSSL_VERSION_SUPPORTED - Success
-- OpenSSL found: 3.0.13
-- Generating embedded license file for target: llama-app
-- Configuring done (6.1s)
-- Generating done (0.3s)
-- Build files have been written to: /opt/llm/llama.cpp/build

...
...
...

[100%] Built target llama-gguf-split
[OK]    23:03:45 - ✓ Primary build completed successfully

=== STEP: Building specific architecture binaries... ===

[INFO]  23:03:45 - Building for architecture: 61
CMAKE_BUILD_TYPE=Release
-- Warning: ccache not found - consider installing it for faster compilation or disable this warning with GGML_CCACHE=OFF
-- CMAKE_SYSTEM_PROCESSOR: x86_64
-- GGML_SYSTEM_ARCH: x86
-- Including CPU backend
-- x86 detected
-- Adding CPU backend variant ggml-cpu: -march=native 
-- CUDA Toolkit found
-- Using CMAKE_CUDA_ARCHITECTURES=61 CMAKE_CUDA_ARCHITECTURES_NATIVE=89-real;61-real
-- CUDA host compiler is GNU 13.3.0
-- Including CUDA backend
-- ggml version: 0.15.2
-- ggml commit:  d0f9d2e5
-- OpenSSL found: 3.0.13
-- Generating embedded license file for target: llama-app
-- Configuring done (0.4s)
-- Generating done (0.4s)
-- Build files have been written to: /opt/llm/llama.cpp/build_61
[  0%] Building CXX object common/CMakeFiles/llama-common-base.dir/build-info.cpp.o
[  1%] Built target llama-ui-embed
[  3%] Building C object ggml/src/CMakeFiles/ggml-base.dir/ggml.c.o
[  3%] Built target cpp-httplib
[  3%] Building CXX object ggml/src/CMakeFiles/ggml-base.dir/ggml.cpp.o
[  3%] Building C object ggml/src/CMakeFiles/ggml-base.dir/ggml-alloc.c.o
[  3%] Building CXX object ggml/src/CMakeFiles/ggml-base.dir/ggml-opt.cpp.o
[  3%] Building CXX object ggml/src/CMakeFiles/ggml-base.dir/ggml-backend.cpp.o
[  3%] Building CXX object ggml/src/CMakeFiles/ggml-base.dir/ggml-backend-meta.cpp.o
[  4%] Building C object ggml/src/CMakeFiles/ggml-base.dir/ggml-quants.c.o
[  4%] Building CXX object ggml/src/CMakeFiles/ggml-base.dir/gguf.cpp.o
[  4%] Building CXX object ggml/src/CMakeFiles/ggml-base.dir/ggml-threading.cpp.o
[  4%] Provisioning UI assets
-- UI: npm output up-to-date, skipping build
[  4%] Linking CXX static library libllama-common-base.a
[  4%] Built target llama-common-base
-- UI: gzip compression applied (/opt/llm/llama.cpp/build_61/tools/ui/dist/_gzip)
[  4%] Built target llama-ui-assets
[  4%] Built target llama-ui
[  4%] Linking CXX shared library ../../bin/libggml-base.so
[  4%] Built target ggml-base
[  4%] Linking CXX shared library ../../bin/libggml-cpu.so
[  7%] Built target ggml-cpu
[  7%] Linking CUDA shared library ../../../bin/libggml-cuda.so
[ 46%] Built target ggml-cuda
[ 46%] Linking CXX shared library ../../bin/libggml.so
[ 46%] Built target ggml
[ 46%] Linking CXX shared library ../bin/libllama.so
[ 81%] Built target llama
[ 81%] Linking CXX shared library ../../bin/libmtmd.so
[ 81%] Linking CXX shared library ../bin/libllama-common.so
[ 89%] Built target mtmd
[ 96%] Built target llama-common
[ 96%] Building CXX object tools/server/CMakeFiles/server-context.dir/server-tools.cpp.o
[ 96%] Linking CXX static library libserver-context.a
[ 98%] Built target server-context
[ 98%] Linking CXX shared library ../../bin/libllama-server-impl.so
[100%] Built target llama-server-impl
[100%] Linking CXX executable ../../bin/llama-server
[100%] Built target llama-server
[OK]    23:04:14 - ✓ Created specific binary: llama-server-61
[INFO]  23:04:14 - Building for architecture: 89
CMAKE_BUILD_TYPE=Release
-- Warning: ccache not found - consider installing it for faster compilation or disable this warning with GGML_CCACHE=OFF
-- CMAKE_SYSTEM_PROCESSOR: x86_64
-- GGML_SYSTEM_ARCH: x86
-- Including CPU backend
-- x86 detected
-- Adding CPU backend variant ggml-cpu: -march=native 
-- CUDA Toolkit found
-- Using CMAKE_CUDA_ARCHITECTURES=89 CMAKE_CUDA_ARCHITECTURES_NATIVE=89-real;61-real
-- CUDA host compiler is GNU 13.3.0
-- Including CUDA backend
-- ggml version: 0.15.2
-- ggml commit:  d0f9d2e5
-- OpenSSL found: 3.0.13
-- Generating embedded license file for target: llama-app
-- Configuring done (0.4s)
-- Generating done (0.4s)
-- Build files have been written to: /opt/llm/llama.cpp/build_89
[  0%] Building CXX object common/CMakeFiles/llama-common-base.dir/build-info.cpp.o
[  1%] Built target llama-ui-embed
[  1%] Built target cpp-httplib
[  1%] Building CXX object ggml/src/CMakeFiles/ggml-base.dir/ggml.cpp.o
[  1%] Building C object ggml/src/CMakeFiles/ggml-base.dir/ggml-alloc.c.o
[  3%] Building C object ggml/src/CMakeFiles/ggml-base.dir/ggml.c.o
[  3%] Building CXX object ggml/src/CMakeFiles/ggml-base.dir/ggml-opt.cpp.o
[  3%] Building CXX object ggml/src/CMakeFiles/ggml-base.dir/ggml-backend-meta.cpp.o
[  3%] Building CXX object ggml/src/CMakeFiles/ggml-base.dir/ggml-backend.cpp.o
[  4%] Building C object ggml/src/CMakeFiles/ggml-base.dir/ggml-quants.c.o
[  4%] Building CXX object ggml/src/CMakeFiles/ggml-base.dir/gguf.cpp.o
[  4%] Building CXX object ggml/src/CMakeFiles/ggml-base.dir/ggml-threading.cpp.o
[  4%] Provisioning UI assets
-- UI: npm output up-to-date, skipping build
[  4%] Linking CXX static library libllama-common-base.a
[  4%] Built target llama-common-base
-- UI: gzip compression applied (/opt/llm/llama.cpp/build_89/tools/ui/dist/_gzip)
[  4%] Built target llama-ui-assets
[  4%] Built target llama-ui
[  4%] Linking CXX shared library ../../bin/libggml-base.so
[  4%] Built target ggml-base
[  4%] Linking CXX shared library ../../bin/libggml-cpu.so
[  7%] Built target ggml-cpu
[  7%] Linking CUDA shared library ../../../bin/libggml-cuda.so
[ 46%] Built target ggml-cuda
[ 46%] Linking CXX shared library ../../bin/libggml.so
[ 46%] Built target ggml
[ 46%] Linking CXX shared library ../bin/libllama.so
[ 81%] Built target llama
[ 81%] Linking CXX shared library ../bin/libllama-common.so
[ 81%] Linking CXX shared library ../../bin/libmtmd.so
[ 89%] Built target mtmd
[ 96%] Built target llama-common
[ 96%] Building CXX object tools/server/CMakeFiles/server-context.dir/server-tools.cpp.o
[ 96%] Linking CXX static library libserver-context.a
[ 98%] Built target server-context
[ 98%] Linking CXX shared library ../../bin/libllama-server-impl.so
[100%] Built target llama-server-impl
[100%] Linking CXX executable ../../bin/llama-server
[100%] Built target llama-server
[OK]    23:04:42 - ✓ Created specific binary: llama-server-89

==================================================
MULTI-ARCHITECTURE BUILD SUMMARY
==================================================
Universal binary (all archs) deployed:
from /opt/llm/llama.cpp/build/bin/llama-server to /opt/llm/llama-server
To deploy specific architecture binaries, use the following commands:
  cp /opt/llm/llama.cpp/build_61/bin/llama-server-61 /opt/llm
  cp /opt/llm/llama.cpp/build_89/bin/llama-server-89 /opt/llm
==================================================
[OK]    23:04:42 - ✓ Build completed successfully
[INFO]  23:04:42 - Starting deployment...
[INFO]  23:04:44 - Deploying binaries from /opt/llm/llama.cpp/build/bin to /opt/llm
[INFO]  23:04:44 - Skipped copy: llama-server is a valid symlink to build dir
[OK]    23:04:44 - ✓ Binaries deployed to /opt/llm (5 files)
[INFO]  23:04:44 - Verifying deployed binaries...
[OK]    23:04:45 - ✓ Binary verification passed (--version)
[INFO]  23:04:45 - Build record saved to /opt/llm/backup/build_history.log
[INFO]  23:04:45 - Starting service llm-server.service...
[OK]    23:04:48 - ✓ Service started successfully
[INFO]  23:04:48 - Displaying service status...

=== SERVICE STATUS: llm-server.service ===

● llm-server.service - LLM Inference Server
     Loaded: loaded (/etc/systemd/system/llm-server.service; enabled; preset: enabled)
     Active: active (running) since Mon 2026-06-22 23:04:45 +12; 3s ago
   Main PID: 1281302 (run_llm.sh)
      Tasks: 70 (limit: 629145)
     Memory: 693.6M (peak: 693.6M)
        CPU: 2.944s
     CGroup: /system.slice/llm-server.service
             ├─1281302 /bin/bash /opt/llm/run_llm.sh
             └─1281303 /opt/llm/llama-server -m /mnt/Models/Qwen3.5-122B-A10B-UD-IQ1_M/Qwen3.5-122B-A10B-UD-IQ1_M.gguf --host 0.0.0.0 --port 8085 --jinja -a sk-no-key-required -fa on --fit on --fit-target 512,256,256,256,256 --context-shift --spec-type ngram-mod --spec-draft-n-max 6 --spec-draft-p-min 0.5 --cache-ram 1024 --cache-prompt --temp 0.6 --top-k 0 --top-p 1.0 --repeat_penalty 1.0 --repeat_last_n 64 --min-p 0.05 --ctx-size 262144 --mlock --no-mmap --batch-size 1024 -ub 256 --cache-type-k q4_1 --cache-type-v q4_1 --parallel 1 -n 65536

        23:04:45 systemd[1]: Started llm-server.service - LLM Inference Server.

[OK]    23:04:48 - ✓ Operation completed successfully
[INFO]  23:04:48 - Ensuring service is running after operation...
[INFO]  23:04:48 - Starting service llm-server.service...
[OK]    23:04:51 - ✓ Service started successfully

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
## Example delta report (diff)
opt/llm/llama.cpp/reports/20260622_225556.txt
```text
Git Changes Summary — llama.cpp
Date: 2026-06-22 22:55:56
Part: 1/1 (commits 1-1 of 1)
Ref: 0ef6f06d553b160d8fc1fba38f5848c7940873a2 → d0f9d2e5ac5d4f51763755958b8f353fed01aaa2
==========================================================================================

Commits in this file: 1

==========================================================================================
Commit 1/1
Hash : d0f9d2e5ac5d4f51763755958b8f353fed01aaa2
Author: Pascal
Date : 2026-06-22
Subject : server: fix edit_file crash on append at end of file (line_start -1) (#24893)

   • tools/server/server-tools.cpp
--- DIFF ---
commit d0f9d2e5ac5d4f51763755958b8f353fed01aaa2
Author: Pascal <admin@serveurperso.com>
Date:   Mon Jun 22 10:55:28 2026 +0200

    server: fix edit_file crash on append at end of file (line_start -1) (#24893)
    
    line_start -1 normalized to n+1, so append inserted at lines.begin() + n + 1,
    one past end() -> heap-buffer-overflow in vector::_M_range_insert.
    
    Normalize -1 to n (insert at end()), restrict -1 to append mode and reject it
    for replace/delete instead of silently clobbering the last line. Parenthesize
    the insert offset so empty-file append computes the position as int first,
    avoiding a transient begin() - 1 on a null vector data pointer.

diff --git a/tools/server/server-tools.cpp b/tools/server/server-tools.cpp
index 95662d4e..790ed85a 100644
--- a/tools/server/server-tools.cpp
+++ b/tools/server/server-tools.cpp
@@ -569,9 +569,13 @@ struct server_tool_edit_file : server_tool {
             }
             int n = (int) lines.size();
             if (e.line_start == -1) {
-                // -1 means end of file; line_end is ignored — normalize to point past last line
-                e.line_start = n + 1;
-                e.line_end   = n + 1;
+                // -1 targets end of file -> valid for append only; line_end is ignored
+                if (e.mode != "append") {
+                    return {{"error", "line_start -1 (end of file) is only valid for append mode"}};
+                }
+                // append at end of file: insert position is the current line count
+                e.line_start = n;
+                e.line_end   = n;
             } else {
                 if (e.line_start < 1 || e.line_end < e.line_start) {
                     return {{"error", string_format("invalid line range [%d, %d]", e.line_start, e.line_end)}};
@@ -612,8 +616,8 @@ struct server_tool_edit_file : server_tool {
             } else if (e.mode == "delete") {
                 lines.erase(lines.begin() + idx_start, lines.begin() + idx_end + 1);
             } else { // append
-                // idx_end + 1 may equal lines.size() when line_start == -1 (end of file)
-                lines.insert(lines.begin() + idx_end + 1, new_lines.begin(), new_lines.end());
+                // insert after idx_end; idx_end + 1 == lines.size() for end-of-file append
+                lines.insert(lines.begin() + (idx_end + 1), new_lines.begin(), new_lines.end());
             }
         }
 

Changed files: 1

==========================================================================================
SUMMARY FOR GROUP 1/1
==========================================================================================
Commits in group: 1
Files changed:    1
Lines added:      9
Lines deleted:    5
Net growth:       4 lines
```




## BPMN Process Flow

```mermaid
flowchart TD
    Start([Start]) --> Lock[Acquire lock file]
    Lock --> LockOK{Lock acquired?}
    LockOK -- No --> LockErr[/Error: Script already running/] --> End1([End])
    LockOK -- Yes --> LoadCfg[Load service config]
    
    LoadCfg --> CheckReq[Check requirements:<br/>GPU, Driver, CUDA, OS,<br/>llama.cpp, Node.js, NCCL]
    
    CheckReq --> ReqOK{All requirements OK?}
    ReqOK -- No --> FixPrompt{Apply automatic fixes?}
    FixPrompt -- Y --> ApplyFix[Install driver/CUDA/Node/NCCL] --> End2([End: Rerun script])
    FixPrompt -- N --> CritFail[/Critical failure/] --> End3([End])
    
    ReqOK -- Yes --> CheckRepo{llama.cpp exists?}
    CheckRepo -- No --> InstallPrompt{Install via install.sh?}
    InstallPrompt -- Y --> RunInstall[Run install.sh] --> End4([End])
    InstallPrompt -- N --> End5([End: Missing repo])
    
    CheckRepo -- Yes --> CheckTools[Check build tools:<br/>git, cmake, make, gcc]
    
    CheckTools --> ToolsOK{All tools present?}
    ToolsOK -- No --> ToolChoice{Choice:}
    ToolChoice -- 1 Install --> InstallTools[Install tools] --> DetectGPU
    ToolChoice -- 2 Skip --> SkipTools[Skip check] --> DetectGPU
    ToolChoice -- 3 Exit --> End6([End])
    
    ToolsOK -- Yes --> DetectGPU[Detect GPUs:<br/>nvidia-smi → CUDA_ARCH]
    
    DetectGPU --> GPUDet{GPUs detected?}
    GPUDet -- No --> FallbackArch[Fallback: CUDA_ARCH=61,<br/>GGML_NATIVE=OFF] --> CheckSvc
    GPUDet -- Yes --> SaveArch[Save unique architectures] --> CheckSvc
    
    CheckSvc[Check service status] --> SavePre[Save PRE_SYNC_COMMIT]
    SavePre --> MainMenu{Select action:}
    
    MainMenu -- 1 Update --> UpdateFlow[Update/Build/Deploy]
    MainMenu -- 2 Rollback --> RollbackFlow[Rollback]
    MainMenu -- 3 Exit --> End7([End: Exit])
    MainMenu -- * --> End8([End: Invalid])
    
    %% UPDATE FLOW
    UpdateFlow --> StopSvc[Stop service]
    StopSvc --> StopOK{Success?}
    StopOK -- No --> End9([End: Stop failed])
    StopOK -- Yes --> CreateBkp[Create backup]
    
    CreateBkp --> BkpDup{Backup for this<br/>commit exists?}
    BkpDup -- Yes --> DupPrompt{Create another?}
    DupPrompt -- Y --> DoBkp[Copy REPO_DIR → backup]
    DupPrompt -- N --> SkipBkp[Skip backup]
    BkpDup -- No --> DoBkp
    
    DoBkp --> GitChoice{Select version:}
    SkipBkp --> GitChoice
    
    GitChoice -- 1 Latest --> GitLatest[git fetch + reset --hard origin/master]
    GitChoice -- 2 Date --> AskDate[Enter date YYYY-MM-DD] --> GitDate[git rev-list --until]
    GitChoice -- 3 Commit --> AskCommit[Enter commit hash] --> GitCommit[git reset --hard]
    GitChoice -- 4 Rebuild --> SkipGit[Skip git checkout]
    GitChoice -- 5 Redeploy --> SkipGit2[Skip git + build]
    GitChoice -- 6 --> End10([End])
    
    GitLatest --> UpToDate{Local == Remote?}
    UpToDate -- Yes --> RebuildPrompt{Rebuild anyway?}
    RebuildPrompt -- N --> End11([End])
    RebuildPrompt -- Y --> SavePost
    UpToDate -- No --> SavePost[Save POST_SYNC_COMMIT]
    
    GitDate --> SavePost
    GitCommit --> SavePost
    SkipGit --> SavePost
    SkipGit2 --> DeltaCheck
    
    SavePost --> DeltaCheck{PRE != POST<br/>and not redeploy?}
    DeltaCheck -- Yes --> DeltaPrompt{Generate delta report?}
    DeltaPrompt -- Y --> GenDelta[Run git_delta.sh] --> BuildCheck
    DeltaPrompt -- N --> BuildCheck
    DeltaCheck -- No --> BuildCheck
    
    BuildCheck{is_redeploy?}
    BuildCheck -- Yes --> DeploySkip[Skip build] --> Deploy
    BuildCheck -- No --> BuildStrategy[decide_build_strategy]
    
    BuildStrategy --> CPUCheck{CPU capabilities}
    CPUCheck -- AVX512 --> AVX512[GGML_NATIVE=ON<br/>+ AVX512 flags]
    CPUCheck -- AVX2 --> AVX2[GGML_NATIVE=ON<br/>+ AVX2 flags]
    CPUCheck -- Old --> OldCPU[GGML_NATIVE=OFF]
    
    AVX512 --> StratConfirm{Use this config?}
    AVX2 --> StratConfirm
    OldCPU --> StratConfirm
    StratConfirm -- N --> StratChoice{Choice: 1-OFF, 2-ON}
    StratChoice --> MultiArchCheck
    StratConfirm -- Y --> MultiArchCheck
    
    MultiArchCheck{Multiple GPU arch?}
    MultiArchCheck -- Yes --> MultiChoice{Build strategy:}
    MultiChoice -- 1 --> SingleBin[Single binary]
    MultiChoice -- 2 --> MultiBin[Multi-arch binaries]
    MultiArchCheck -- No --> SingleBin
    
    SingleBin --> PerformBuild[perform_build:<br/>cmake configure → cmake build]
    MultiBin --> PerformBuild
    
    PerformBuild --> CMakeOK{CMake OK?}
    CMakeOK -- No --> UpdateFail
    CMakeOK -- Yes --> MakeOK{Make OK?}
    MakeOK -- No --> UpdateFail
    MakeOK -- Yes --> Deploy
    
    Deploy[deploy_binaries] --> DiagCheck{Diagnostics:}
    DiagCheck -- SOURCE_NOT_FOUND --> DeployErr
    DiagCheck -- NO_BINARIES --> DeployErr
    DiagCheck -- DEST_NOT_FOUND --> DeployErr
    DiagCheck -- NO_WRITE_PERMISSION --> DeployErr
    DiagCheck -- FILES_LOCKED --> DeployErr
    DiagCheck -- LOW_DISK_SPACE --> DeployErr
    DiagCheck -- COPY_FAILED --> DeployErr
    DiagCheck -- OK --> VerifyBin
    
    DeployErr[handle_deployment_failure] --> RetryChoice{Choice:}
    RetryChoice -- 1 Retry --> FixIssue[Fix issue → Enter] --> Deploy
    RetryChoice -- 2 Restore --> RestoreBkp[restore_backup_path] --> End12([End])
    RetryChoice -- 3 Exit --> End13([End])
    
    VerifyBin[verify_binaries] --> VerifyOK{OK?}
    VerifyOK -- No --> UpdateFail
    VerifyOK -- Yes --> SaveLog[save_build_log]
    
    SaveLog --> StartSvc[start_service]
    StartSvc --> SvcOK{OK?}
    SvcOK -- No --> UpdateFail
    SvcOK -- Yes --> ShowStatus[display_service_status] --> End14([End: Success])
    
    UpdateFail[handle_update_failure] --> RollbackPrompt{Restore backup?}
    RollbackPrompt -- Y --> AutoRestore[restore_backup_path] --> End15([End])
    RollbackPrompt -- N --> End16([End: Backup preserved])
    
    %% ROLLBACK FLOW
    RollbackFlow --> StopSvc2[Stop service]
    StopSvc2 --> ListBkp[list_backups]
    ListBkp --> AskBkpID[Enter backup ID]
    AskBkpID --> ConfirmRestore{Confirm restore?}
    ConfirmRestore -- N --> End17([End: Skipped])
    ConfirmRestore -- Y --> DoRestore[cp backup → REPO_DIR]
    
    DoRestore --> CompleteRb[complete_rollback]
    CompleteRb --> DeployRb[deploy_binaries]
    DeployRb --> DeployRbOK{OK?}
    DeployRbOK -- No --> End18([End: Rollback failed])
    DeployRbOK -- Yes --> VerifyRb[verify_binaries]
    VerifyRb --> StartSvcRb[start_service]
    StartSvcRb --> ShowStatusRb[display_service_status] --> End19([End: Rollback success])
```