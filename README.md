# oblaQ Spirula Studio RunPod image

`dakord/spirula-studio:latest` is the Spirula Studio CLI (`spirula`, pinned release, Vulkan backend) plus oblaQ's custom GPU-BA COLMAP, taken from `dakord/oblaq-colmap-base:latest`, in one pod image with SSH.

## Why it isn't a plain `FROM oblaq-colmap-base`

The prebuilt `spirula` binary needs **glibc 2.38 (Ubuntu 24.04+)**, and colmap-base is Ubuntu 22.04 (glibc 2.35). So the runtime is `nvidia/cuda:13.0.0-runtime-ubuntu24.04` (the same CUDA version as colmap-base). COLMAP and the `.so` files it actually links against (found with `ldd`) are copied in from colmap-base. `/usr/local/bin/colmap` is a wrapper that puts those libraries on the path only for COLMAP, so they can't affect spirula.

## Repo setup (same as LFStudio)

1. Create a new GitHub repo (public, so Actions minutes are free), e.g. `ftalijic/SpirulaStudio`, and push this folder to it.
2. Add the `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` repo secrets (the same values as in the LFStudio repo).
3. Pushing to `main` builds the image automatically. You can also run it manually from Actions → *Build and push Spirula Studio image*. The build takes minutes because nothing is compiled.

To bump Spirula, edit `SPIRULA_VERSION` and `SPIRULA_SHA256` in the Dockerfile. For the checksum, use `sha256sum spirula-<ver>-ubuntu-vulkan-x86_64.zip` or the digest shown on the GitHub release page.

## Deploying on RunPod

- Use a Custom Container with the image `dakord/spirula-studio:latest`.
- Expose TCP 22 for SSH. For the training viewer, either expose HTTP 7007 or use `ssh -L 7007:localhost:7007 ...`.
- Attach the network volume at `/workspace`. Model checkpoints are cached in `/workspace/.cache`.

## First-boot smoke test

```bash
cat /root/vulkan-check.log     # GPU name + Vulkan apiVersion; should NOT show ERROR
spirula sam devices            # must list the GPU as meeting the baseline (Vulkan 1.2 + BDA + timeline semaphores)
colmap -h | head -3            # "COLMAP 4.x ... with CUDA"
```

If `spirula sam devices` says "no Vulkan devices were found", the host isn't giving the container the driver's graphics/Vulkan libraries. The image sets `NVIDIA_DRIVER_CAPABILITIES=all` and ships a fallback ICD file, so check `ls /usr/lib/x86_64-linux-gnu/libGLX_nvidia*`. If nothing is there, try a different GPU type or datacenter.

## Typical CLI runs (inside `tmux`)

```bash
# SfM straight from images (COLMAP-format output), or use our COLMAP instead
spirula sfm auto --help

# Train on an existing COLMAP dataset (sparse/0 + images/ + optional masks/)
spirula train 3dgs --data /workspace/data --data-format colmap \
    --colmap-recon-dir sparse/0 \
    --output-dir-prefix /workspace/output --num-iterations 30000

# 360 / fisheye originals without undistorting
spirula train 360-camera --data /workspace/data ...

# All flags (138 extra tuning flags behind this)
spirula train --help-all
```

## Notes

- Spirula is GPL-3.0. Running it is fine. Redistributing the image publicly means GPL obligations apply to the binary inside it, which is the same situation as COLMAP (BSD) and LichtFeld (GPL).
