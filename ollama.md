# Local Coding Assistant Setup: Qwen3-Coder + Ollama + Continue.dev on HPC Cluster

## Overview

Run a free, local AI coding assistant on a cluster GPU node (NVIDIA L40S, 48GB VRAM) and connect to it from a local WSL VS Code via SSH tunnel.

**Stack:** Ollama → Qwen3-Coder-30B-A3B (Q8) → SSH tunnel → Continue.dev in VS Code

---

## Prerequisites

- Access to an HPC cluster with an NVIDIA GPU node (tested on L40S 48GB)
- SSH access: local WSL → login node → GPU node
- Shared filesystem between login and GPU nodes (e.g., GPFS mounted at `/h`)
- Conda available on the cluster

---

## Step 1 — Install Ollama on GPU Node (No Sudo Required)

The standard `curl | sh` installer requires root. Use the tarball method instead.

```bash
# SSH to the GPU node

# Download the tarball (format is .tar.zst, NOT .tgz)
curl -fsSL https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64.tar.zst \
  -o ~/ollama-linux-amd64.tar.zst

# You may need zstd — install via conda if not available:
#   conda install -c conda-forge zstd

# Extract to ~/.local
mkdir -p ~/.local
tar --use-compress-program=unzstd -C ~/.local -xf ~/ollama-linux-amd64.tar.zst

# Add to PATH and library path
export PATH=$HOME/.local/bin:$PATH
export LD_LIBRARY_PATH=$HOME/.local/lib/ollama:$LD_LIBRARY_PATH

# IMPORTANT: Add these two lines to your ~/.bashrc so they persist
echo 'export PATH=$HOME/.local/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=$HOME/.local/lib/ollama:$LD_LIBRARY_PATH' >> ~/.bashrc

# Verify
ollama --version
# Expected: "Warning: could not connect to a running Ollama instance" + version number
```

## Step 2 — Start Ollama Server on GPU Node

```bash
# On the GPU node
ollama serve > ~/ollama.log 2>&1 &

# Wait a moment, then verify
sleep 3
curl http://localhost:11434/api/tags
# Expected: {"models":[]}

# Check GPU is detected
cat ~/ollama.log | grep -i gpu
```

## Step 3 — Download the Model from HuggingFace

The Ollama registry (`registry.ollama.ai`) may be blocked or slow on HPC networks. Workaround: download the GGUF from HuggingFace and import into Ollama.

This can be done from the **login node** if the filesystem is shared.

```bash
# On the login node (or GPU node — either works with shared filesystem)

# Create a dedicated conda environment
conda create -n ollama-setup python=3.11 -y
conda activate ollama-setup

# Install HuggingFace CLI
pip install huggingface_hub

# Download the Q8 GGUF (~32GB)
hf download ggml-org/Qwen3-Coder-30B-A3B-Instruct-Q8_0-GGUF \
  --local-dir ~/ollama-models
```

### Finding the correct repo name

If you need to search for a different model/quant:

```bash
hf models ls --search "Qwen3-Coder-30B GGUF" --limit 10

# The display truncates names. Use --format json to see full IDs:
hf models ls --search "ggml-org Qwen3-Coder-30B" --limit 3 --format json
```

### Note on `huggingface-cli`

The old `huggingface-cli` command is deprecated. Use `hf` instead:

```bash
# Old (broken):  huggingface-cli download ...
# New (correct): hf download ...
```

## Step 4 — Import Model into Ollama (TODO)

*Next: create an Ollama Modelfile pointing to the downloaded GGUF and import it.*

## Step 5 — SSH Tunnel from WSL to GPU Node (TODO)

```bash
# From WSL
ssh -L 11434:localhost:11434 -J login-node gpu-node
```

Or add to `~/.ssh/config`:

```
Host gpu-tunnel
    HostName gpu-node
    User your-username
    ProxyJump login-node
    LocalForward 11434 localhost:11434
```

## Step 6 — Install and Configure Continue.dev in VS Code (TODO)

1. Install Continue extension in VS Code
2. Configure `~/.continue/config.yaml` to point to `localhost:11434`

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `curl -fsSL https://ollama.com/install.sh` asks for sudo | Standard installer needs root | Use tarball method (Step 1) |
| Ollama download URL returns "Not Found" (9 bytes) | Old `.tgz` URL is dead; format changed to `.tar.zst` | Download from GitHub releases |
| `ollama pull` gives TLS handshake timeout | `registry.ollama.ai` blocked/slow on cluster | Download GGUF from HuggingFace instead (Step 3) |
| `huggingface-cli` says deprecated | CLI was renamed | Use `hf` command instead |
| HuggingFace repo "not found" | Repo name truncated in search results | Use `--format json` to see full repo IDs |

---

## Hardware Notes

- **Model:** Qwen3-Coder-30B-A3B-Instruct (MoE: 30B total, 3.3B active per token)
- **Quantization:** Q8_0 (~32GB) — fits on 48GB GPU with room for long context
- **GPU:** NVIDIA L40S (48GB VRAM, Ada Lovelace, compute capability 8.9)
- **Alternative:** Q4_K_M (~18.6GB) if you want maximum context window headroom
