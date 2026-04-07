# Isaac Lab Installation on ABB HPC Cluster (SLES 15, L40S)

A step-by-step guide for installing NVIDIA Isaac Lab on ABB's HPC cluster without containers, using conda.

## Stack

- **Isaac Sim 5.x** — physics/rendering engine (pip-installable)
- **Isaac Lab** — RL framework on top of Isaac Sim
- **Python 3.11** — required by Isaac Sim 5.x

## Prerequisites

| Requirement       | Minimum                  | This Cluster             |
|-------------------|--------------------------|--------------------------|
| GPU               | NVIDIA with RT cores     | L40S (48 GB VRAM) ✓     |
| Driver            | ≥ 580.65.06              | 580.82.07 ✓              |
| CUDA (driver)     | ≥ 12.x                  | 13.0 ✓                   |
| GLIBC             | ≥ 2.35                  | 2.38 ✓                   |
| OS                | Linux (Ubuntu 22.04+)   | SLES 15.7 ✓              |

> **Important:** GPUs without RT cores (A100, H100) are **not supported** by Isaac Sim. Use L40S nodes.

## 1. Fix SSL Certificates (ABB Network)

The ABB corporate proxy intercepts HTTPS traffic with a custom root CA (`ABB_RSA_Root_CA_G1`). Both pip and conda will fail without this fix.

### Set environment variables

Add to `~/.bashrc`:

```bash
export REQUESTS_CA_BUNDLE=/etc/ssl/ca-bundle.pem
export SSL_CERT_FILE=/etc/ssl/ca-bundle.pem
```

Then reload:

```bash
source ~/.bashrc
```

### Configure conda

```bash
conda config --set ssl_verify /etc/ssl/ca-bundle.pem
```

### Inject ABB CA into Python's certifi

This must be re-run every time you recreate the conda environment, since certifi gets reinstalled fresh.

```bash
conda activate isaaclab  # activate env first (after creating it in step 2)
cat /etc/ssl/certs/ABB_RSA_Root_CA_G1.pem >> $(python -c "import certifi; print(certifi.where())")
```

## 2. Create Conda Environment (Login Node)

```bash
conda create -n isaaclab python=3.11 -y
conda activate isaaclab
pip install --upgrade pip packaging wheel
```

After creating the environment, run the certifi injection from Step 1.

## 3. Install Isaac Sim (Login Node)

```bash
pip install 'isaacsim[all,extscache]' --extra-index-url https://pypi.nvidia.com
```

Accept the EULA (or set it in advance):

```bash
export OMNI_KIT_ACCEPT_EULA=YES
```

> The first run will pull extensions from the Omniverse registry (~10+ minutes). Subsequent runs use the cache.

## 4. Install PyTorch (Login Node)

Check available CUDA versions for conda:

```bash
conda search pytorch-cuda -c pytorch -c nvidia
```

Install with the latest available CUDA toolkit (backward-compatible with your driver):

```bash
conda install pytorch torchvision pytorch-cuda=12.4 -c pytorch -c nvidia
```

> Your driver (580, CUDA 13.0) can run any older CUDA toolkit, so `pytorch-cuda=12.4` works fine.

## 5. Install Missing Libraries (Login Node)

Isaac Sim requires `libGLU` which is not installed system-wide. Install via conda:

```bash
conda install -c conda-forge libglu
```

Add the conda lib path so Isaac Sim can find it at runtime. Add to `~/.bashrc`:

```bash
export LD_LIBRARY_PATH=$CONDA_PREFIX/lib:$LD_LIBRARY_PATH
```

## 6. Launch Compute Node

```bash
qsub -I -l feature=gpu_l40s,nodes=1:ppn=36,walltime=4:00:00
```

> Do **not** use `-X` flag — there is no X11/xauth on the login nodes and you don't need it for headless training.

Once on the compute node, verify GPU access:

```bash
nvidia-smi
```

## 7. Install Isaac Lab (Compute Node)

```bash
conda activate isaaclab
export OMNI_KIT_ACCEPT_EULA=YES

cd ~
git clone https://github.com/isaac-sim/IsaacLab.git
cd IsaacLab
./isaaclab.sh --install
```

This installs all Isaac Lab extensions and RL libraries (rsl_rl, skrl, sb3, rl_games).

## 8. Verify

```bash
./isaaclab.sh -p scripts/reinforcement_learning/rsl_rl/train.py --task=Isaac-Ant-v0 --headless
```

## Remote Display (WebRTC Livestream)

Isaac Lab supports WebRTC livestreaming, allowing you to view the simulation remotely from your local machine. This requires **3 terminals**.

### Terminal 1 — Compute node (run training with livestream)

```bash
conda activate isaaclab
export OMNI_KIT_ACCEPT_EULA=YES

cd ~/IsaacLab
./isaaclab.sh -p scripts/reinforcement_learning/rsl_rl/train.py --task=Isaac-Ant-v0 --livestream 2
```

Wait until you see `Streaming server started` and `Simulation App Startup Complete`.

Note the compute node hostname (e.g. `gpu40`).

### Terminal 2 — SSH tunnel from your local machine

```bash
ssh -L 49100:<compute_node>:49100 segaram@simulation.abb.com
```

Replace `<compute_node>` with the hostname from Terminal 1 (e.g. `gpu40`). Keep this open.

### Terminal 3 — Isaac Sim WebRTC Streaming Client (local machine)

The pip-installed Isaac Sim does **not** serve a browser-based WebRTC client. You need the standalone **Isaac Sim WebRTC Streaming Client** app.

Download it from the [Isaac Sim Latest Release page](https://docs.isaacsim.omniverse.nvidia.com/latest/installation/download.html) for your platform (Windows/macOS/Linux). It is a lightweight app (~100 MB) — not the full Isaac Sim.

1. Open the Isaac Sim WebRTC Streaming Client
2. Enter `127.0.0.1` as the server address
3. Click **Connect**

> Each Isaac Sim instance supports only one streaming client at a time.

## GPU Monitoring

```bash
# Real-time GPU monitoring (always available)
watch -n 1 nvidia-smi

# Compact GPU utilization stream
nvidia-smi dmon -s u

# Or install nvtop for a nicer TUI
conda install -c conda-forge nvtop
nvtop
```

## PBS Job Script Template

```bash
#!/bin/bash
#PBS -l feature=gpu_l40s,nodes=1:ppn=36,walltime=8:00:00

# Environment
source ~/.bashrc
conda activate isaaclab
export OMNI_KIT_ACCEPT_EULA=YES

# Training
cd ~/IsaacLab
./isaaclab.sh -p scripts/reinforcement_learning/rsl_rl/train.py \
    --task=Isaac-Velocity-Rough-Anymal-C-v0 \
    --headless \
    --num_envs 4096
```

Submit with:

```bash
qsub job_script.sh
```

## Troubleshooting

### SSL errors from pip or conda

Re-run the certifi injection (Step 1). This is needed after any `pip install` that upgrades certifi.

```bash
cat /etc/ssl/certs/ABB_RSA_Root_CA_G1.pem >> $(python -c "import certifi; print(certifi.where())")
```

### `pytorch-cuda=12.8` not found

Not yet packaged for conda. Use `12.4` or `12.6` — backward-compatible with your CUDA 13.0 driver.

### `libGLU.so.1: cannot open shared object file`

```bash
conda install -c conda-forge libglu
export LD_LIBRARY_PATH=$CONDA_PREFIX/lib:$LD_LIBRARY_PATH
```

### `ModuleNotFoundError: No module named 'isaacsim'`

Ensure the conda environment is activated and, if using binaries, that `source _isaac_sim/setup_conda_env.sh` has been executed.

### `libgomp` preload conflict

```bash
unset LD_PRELOAD
export LD_PRELOAD="/usr/lib64/libgomp.so.1"
```

### First run takes very long

Normal. Isaac Sim pulls dependent extensions from the Omniverse registry on first launch (~10+ min). Cached afterward.

### WebRTC browser URL returns `{"detail":"Not Found"}`

The pip-installed Isaac Sim does not include the browser-based WebRTC client HTML files. Use the standalone Isaac Sim WebRTC Streaming Client app instead (see Remote Display section above).
