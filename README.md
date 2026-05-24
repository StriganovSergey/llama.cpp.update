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

## Example Console Output



```text
==================================================
    LLM Update Script v4.6 — DFD Compliant
    Repo: /opt/llm/llama.cpp
==================================================
[INFO]  19:42:03 - Loaded service config: llm.service
[DEBG]  19:42:03 - ℹ️  Added /usr/local/cuda-12.8/bin to PATH for CUDA detection

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

[INFO]  19:42:03 - Detecting NVIDIA GPUs...
[DEBG]  19:42:03 - ℹ️  GPU 1: Compute Capability 6.1 → 61
[OK]    19:42:03 - ✓ Detected 1 GPU(s). Architectures: 61
[WARN]  19:42:03 - ⚠️  Pascal detected → GGML_NATIVE=OFF
[INFO]  19:42:04 - Service llm.service is currently ACTIVE
[OK]    19:42:04 - ✓ Service name saved: llm.service

Select action:
  [1] Update / Build
  [2] Rollback to previous build
  [3] Exit
Selection: 1

=== STEP: Updating llama.cpp ===

[INFO]  19:42:11 - Stopping service llm.service...
[INFO]  19:42:12 - Creating backup → /opt/llm/backup/backup_20260524_194212
[OK]    19:42:29 - ✓ Backup created: backup_20260524_194212
[OK]    19:42:29 - ✓ OS: Ubuntu 24.04 confirmed
[INFO]  19:42:30 - Driver: 570.211.01 | GPU: NVIDIA P102-100 | Memory: 10240MB
[DEBG]  19:42:30 - ℹ️  NCCL already installed
[OK]    19:42:30 - ✓ npm already installed (10.8.2)

Select version to build:
  [1] Latest (master)
  [2] By date (YYYY-MM-DD)
  [3] By commit
Choice [1]: 1

