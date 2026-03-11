# isaaclab-demo

This image is intended for Isaac Sim / Isaac Lab under Docker on Linux or WSL2.

## Why the current container fails

If Isaac Sim logs show messages like `No device could be created`, `GPU Foundation is not initialized`, or `CUDA libs are present, but no suitable CUDA GPU was found`, the container was usually started with CUDA-only NVIDIA capabilities.

Isaac Sim needs NVIDIA graphics/Vulkan driver libraries inside the container, not only `compute,utility`.

## Build

```bash
docker build -t isaaclab .
```

## Run on WSL2

Recreate the container with NVIDIA graphics capabilities enabled:

```bash
docker run --rm -it \
	--gpus all \
	--runtime=nvidia \
	-e NVIDIA_VISIBLE_DEVICES=all \
	-e NVIDIA_DRIVER_CAPABILITIES=all \
	-e DISPLAY=$DISPLAY \
	-e WAYLAND_DISPLAY=$WAYLAND_DISPLAY \
	-e XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR \
	-v /tmp/.X11-unix:/tmp/.X11-unix:rw \
	-v /mnt/wslg:/mnt/wslg:rw \
	-v "$PWD":/workspace \
	isaaclab
```

For headless test runs, the critical part is still `NVIDIA_DRIVER_CAPABILITIES=all` or at least `graphics,display,video,compute,utility`.

## Quick verification inside the container

```bash
nvidia-smi
printenv NVIDIA_DRIVER_CAPABILITIES
vulkaninfo --summary
```

`nvidia-smi` alone is not sufficient. If `vulkaninfo` cannot enumerate the NVIDIA driver, Isaac Sim will still fail during renderer initialization.
