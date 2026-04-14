# Local Coding Assistant Setup: Qwen3-Coder + Ollama + Continue.dev on HPC Cluster

## Overview

Run a free, local AI coding assistant on a cluster GPU node (NVIDIA L40S, 48GB VRAM) and connect to it from a local WSL VS Code via SSH tunnel.

**Stack:** Ollama → Qwen3-Coder-30B-A3B (Q8) → SSH tunnel → Continue.dev in VS Code

**Network path:** WSL VS Code → `localhost:11434` → SSH tunnel → `simulation.abb.com` → `gpu40` → Ollama server

---

## Prerequisites

- Access to the HPC cluster with a GPU node (`gpu40` with NVIDIA L40S 48GB)
- SSH access: WSL → `simulation.abb.com` (login node) → `gpu40` (GPU node)
- Shared GPFS filesystem between login and GPU nodes (mounted at `/h`)
- Conda available on the cluster
- VS Code with WSL on your local machine

---

## One-Time Setup

### Step 1 — Install Ollama on GPU Node (No Sudo)

SSH to the GPU node:

```bash
ssh segaram@simulation.abb.com
ssh gpu40
```

The standard `curl | sh` installer requires root. Use the tarball method instead. The download format is `.tar.zst` (not `.tgz` — that URL is dead and returns "Not Found").

```bash
# Download from GitHub releases
curl -fsSL https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64.tar.zst \
  -o ~/ollama-linux-amd64.tar.zst

# If zstd is not available, install via conda:
#   conda install -c conda-forge zstd

# Extract to ~/.local (no sudo needed)
mkdir -p ~/.local
tar --use-compress-program=unzstd -C ~/.local -xf ~/ollama-linux-amd64.tar.zst

# Add to PATH and library path
export PATH=$HOME/.local/bin:$PATH
export LD_LIBRARY_PATH=$HOME/.local/lib/ollama:$LD_LIBRARY_PATH

# Make it permanent
echo 'export PATH=$HOME/.local/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=$HOME/.local/lib/ollama:$LD_LIBRARY_PATH' >> ~/.bashrc

# Verify
ollama --version
# Expected: "Warning: could not connect to a running Ollama instance" + version number (e.g., 0.20.7)
```

### Step 2 — Download the Model from HuggingFace

The Ollama registry (`registry.ollama.ai`) may be blocked or slow on HPC networks. Workaround: download the GGUF directly from HuggingFace and import it into Ollama.

This can be done from either node since the filesystem is shared. We use the **login node** (`neo`):

```bash
ssh segaram@simulation.abb.com

# Create a dedicated conda environment
conda create -n ollama-setup python=3.11 -y
conda activate ollama-setup

# Install HuggingFace CLI
pip install huggingface_hub
```

The old `huggingface-cli` command is deprecated. Use `hf` instead.

Search results truncate repo names. Use `--format json` to see full IDs:

```bash
hf models ls --search "ggml-org Qwen3-Coder-30B" --limit 3 --format json
```

Download the Q8 GGUF (~32GB):

```bash
hf download ggml-org/Qwen3-Coder-30B-A3B-Instruct-Q8_0-GGUF \
  --local-dir ~/ollama-models
```

Verify:

```bash
ls -lh ~/ollama-models/*.gguf
# Expected: ~31GB file named qwen3-coder-30b-a3b-instruct-q8_0.gguf
```

### Step 3 — Create Modelfile and Import into Ollama

Back on the **GPU node** (`gpu40`). The Modelfile must include the full Qwen3-Coder tool-calling template, otherwise Continue.dev's Plan and Agent modes won't work (you'll get "does not support tools" errors).

First, start the Ollama server:

```bash
ollama serve > ~/ollama.log 2>&1 &
sleep 3
curl http://localhost:11434/api/tags
# Expected: {"models":[]}
```

Create the Modelfile with full tool-calling support:

```bash
cat > ~/ollama-models/Modelfile << 'OUTER'
FROM /h/segaram/ollama-models/qwen3-coder-30b-a3b-instruct-q8_0.gguf

PARAMETER temperature 0.7
PARAMETER top_p 0.8
PARAMETER repeat_penalty 1.05
PARAMETER top_k 20
PARAMETER num_ctx 32768
PARAMETER stop <|im_start|>
PARAMETER stop <|im_end|>
PARAMETER stop <|endoftext|>
PARAMETER stop </tool_call>

TEMPLATE """{{ if .Messages }}
{{- if or .System .Tools }}<|im_start|>system
{{ .System }}
{{- if .Tools }}

# Tools

You are provided with function signatures within <tools></tools> XML tags:
<tools>{{- range .Tools }}
{"type": "function", "function": {{ .Function }}}{{- end }}
</tools>

For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:
<tool_call>
{"name": <function-name>, "arguments": <args-json-object>}
</tool_call>
{{- end }}<|im_end|>
{{ end }}
{{- range $i, $_ := .Messages }}
{{- $last := eq (len (slice $.Messages $i)) 1 -}}
{{- if eq .Role "user" }}<|im_start|>user
{{ .Content }}<|im_end|>
{{ else if eq .Role "assistant" }}<|im_start|>assistant
{{ if .Content }}{{ .Content }}
{{- else if .ToolCalls }}<tool_call>
{{ range .ToolCalls }}{"name": "{{ .Function.Name }}", "arguments": {{ .Function.Arguments }}}
{{ end }}</tool_call>
{{- end }}{{ if not $last }}<|im_end|>
{{ end }}
{{- else if eq .Role "tool" }}<|im_start|>user
<tool_response>
{{ .Content }}
</tool_response><|im_end|>
{{ end }}
{{- if and (ne .Role "assistant") $last }}<|im_start|>assistant
{{ end }}
{{- end }}
{{- else }}
{{ .Prompt }}
{{- end }}"""
OUTER
```

Import into Ollama:

```bash
ollama create qwen3-coder:30b-q8 -f ~/ollama-models/Modelfile
# Expected: "success"
```

Test basic generation:

```bash
ollama run qwen3-coder:30b-q8 "Write a Python hello world"
```

Test tool calling:

```bash
curl http://localhost:11434/api/chat -d '{
  "model": "qwen3-coder:30b-q8",
  "messages": [{"role": "user", "content": "What is the weather in Stockholm?"}],
  "tools": [{"type": "function", "function": {"name": "get_weather", "description": "Get weather for a city", "parameters": {"type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"]}}}],
  "stream": false
}'
# Expected: response containing "tool_calls" field
```

### Step 4 — SSH Tunnel from WSL to GPU Node

On your **local WSL machine**:

```bash
ssh -L 11434:localhost:11434 -J segaram@simulation.abb.com segaram@gpu40
# Keep this terminal open
```

Verify from a second WSL terminal:

```bash
curl http://localhost:11434/api/tags
# Should show: qwen3-coder:30b-q8
```

Optional: add to `~/.ssh/config` on WSL for convenience:

```
Host gpu-tunnel
    HostName gpu40
    User segaram
    ProxyJump segaram@simulation.abb.com
    LocalForward 11434 localhost:11434
```

Then just run `ssh gpu-tunnel` to open the tunnel.

### Step 5 — Configure Continue.dev in VS Code

On your **local machine**:

1. Open VS Code
2. Go to Extensions (Ctrl+Shift+X), search **"Continue"**, install it
3. Click the Continue icon in the left sidebar
4. Select **Ollama** as provider
5. Set Model to `qwen3-coder:30b-q8`
6. Click **Connect**

Continue stores its config on **Windows** (not WSL) at:

```
C:\Users\SEGARAM\.continue\config.yaml
```

The config should look like:

```yaml
name: Local Coding Assistant
version: 1.0.0
schema: v1
models:
  - name: Qwen3-Coder-30B
    provider: ollama
    model: qwen3-coder:30b-q8
    roles:
      - chat
      - edit
      - apply
context:
  - provider: code
  - provider: diff
  - provider: terminal
  - provider: problems
  - provider: folder
```

After any config change, **close and reopen VS Code** to reload Continue.

---

## Daily Startup Sequence

Run these every time after a restart or session timeout. Three WSL terminals.

**Terminal 1 — Start Ollama on GPU node:**

```bash
ssh -J segaram@simulation.abb.com segaram@gpu40
ollama serve > ~/ollama.log 2>&1 &
sleep 3
curl http://localhost:11434/api/tags
# Should show: qwen3-coder:30b-q8
```

**Terminal 2 — Open the SSH tunnel:**

```bash
ssh -L 11434:localhost:11434 -J segaram@simulation.abb.com segaram@gpu40
# Keep this terminal open — closing it kills the tunnel
```

**Terminal 3 — Verify the tunnel:**

```bash
curl http://localhost:11434/api/tags
# Should show the model listed
```

**Then open VS Code** and use Continue (Chat, Plan, or Agent mode).

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `curl -fsSL https://ollama.com/install.sh` asks for sudo | Standard installer needs root | Use tarball method (Step 1) |
| Ollama download URL returns "Not Found" (9 bytes) | Old `.tgz` URL is dead; format is now `.tar.zst` | Download from GitHub releases |
| `ollama pull` gives TLS handshake timeout | `registry.ollama.ai` blocked/slow on cluster | Download GGUF from HuggingFace instead (Step 2) |
| `huggingface-cli` says deprecated | CLI was renamed | Use `hf` command instead |
| HuggingFace repo "not found" | Repo name truncated in search display | Use `--format json` to see full repo IDs |
| `ollama create` says "could not connect" | Ollama server not running on GPU node | Run `ollama serve > ~/ollama.log 2>&1 &` first |
| Continue shows "does not support tools" | Modelfile missing tool-calling template | Recreate model with full Modelfile from Step 3 |
| Continue config not taking effect | Config lives on Windows, not WSL | Edit `C:\Users\SEGARAM\.continue\config.yaml` |
| `curl http://localhost:11434` fails from WSL | SSH tunnel dropped | Reopen tunnel (Terminal 2 in startup sequence) |
| Model responds but slow / not using GPU | Ollama fell back to CPU | Check `nvidia-smi` on GPU node; check `~/ollama.log` for GPU errors |
| Home directory quota full | Model files are ~32GB | Symlink `~/.ollama` to scratch: `ln -s /path/to/scratch/.ollama ~/.ollama` |

---

## Hardware Notes

- **Model:** Qwen3-Coder-30B-A3B-Instruct (MoE: 30B total, 3.3B active per token)
- **Quantization:** Q8_0 (~32GB) — fits on 48GB GPU with room for 32K context
- **GPU:** NVIDIA L40S (48GB VRAM, Ada Lovelace, compute capability 8.9)
- **Performance:** ~130 tokens/sec generation speed observed
- **Alternative:** Q4_K_M (~18.6GB) if you want maximum context window headroom or to free GPU for other work
