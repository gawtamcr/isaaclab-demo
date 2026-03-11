FROM nvidia/cuda:12.6.3-cudnn-devel-ubuntu22.04

# Avoid interactive prompts during apt installs
ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm

# Enable all NVIDIA driver capabilities (graphics, video, compute)
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=all

# System dependencies
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3.10-dev \
    python3-pip \
    git \
    cmake \
    build-essential \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    x11-apps \
    #sdas
    libglu1-mesa \
    zenity \
    libxrandr2 \
    libxcursor1 \
    libxinerama1 \
    libxi6 \
    libvulkan1 \
    vulkan-tools \
  && rm -rf /var/lib/apt/lists/*

# Make python3.10 the default python
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1 \
 && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1

# Upgrade pip
RUN python -m pip install --upgrade pip

# Install Isaac Sim via pip (NVIDIA's PyPI index)
RUN pip install \
    isaacsim==4.5.0 \
    isaacsim-rl==4.5.0 \
    isaacsim-replicator==4.5.0 \
    isaacsim-extscache-physics==4.5.0 \
    isaacsim-extscache-kit==4.5.0 \
    isaacsim-extscache-kit-sdk==4.5.0 \
    --extra-index-url https://pypi.nvidia.com \
    --extra-index-url https://pypi.org/simple

# Clone and install IsaacLab
RUN git clone https://github.com/isaac-sim/IsaacLab.git /isaac-lab
WORKDIR /isaac-lab
RUN ./isaaclab.sh --install

# Extra Python packages
RUN pip install stable-baselines3 wandb tensorboard

# Mount point for user project code
WORKDIR /workspace

CMD ["/bin/bash"]
