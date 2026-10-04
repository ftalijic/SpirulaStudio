# syntax=docker/dockerfile:1
#
# Spirula Studio CLI (+ oblaQ's custom COLMAP) as a reusable RunPod image.
#
# Unlike the LichtFeld image there is NO compile step here: Spirula ships an
# official prebuilt Ubuntu x86_64 binary on its GitHub releases page (one
# self-contained ~167 MB executable, Vulkan backend), so this image just
# downloads a pinned release and verifies its checksum. Build time is minutes.
#
# Why this is NOT simply `FROM dakord/oblaq-colmap-base:latest`:
#   The prebuilt `spirula` binary needs GLIBC_2.38 / GLIBCXX_3.4.32, i.e.
#   Ubuntu 24.04+. oblaq-colmap-base is Ubuntu 22.04 (glibc 2.35) - spirula
#   would fail to start on it ("version `GLIBC_2.38' not found"). So the
#   runtime here is CUDA 13.0 / Ubuntu 24.04, and COLMAP is pulled OUT of
#   oblaq-colmap-base (same CUDA 13.0.0 major as that image) together with
#   its exact .so closure, discovered via ldd rather than guessed. COLMAP is
#   run through a small wrapper that puts only its own vendored libs on
#   LD_LIBRARY_PATH, so the 22.04 libs never leak into spirula or anything
#   else on the box.
#
# Vulkan on RunPod: spirula uses Vulkan (needs Vulkan 1.2 +
# bufferDeviceAddress + timelineSemaphore), not CUDA. The NVIDIA container
# runtime only mounts the driver's Vulkan/graphics libs when
# NVIDIA_DRIVER_CAPABILITIES includes `graphics` - the nvidia/cuda base images
# default to `compute,utility`, which would make spirula report "no Vulkan
# devices were found". Overridden to `all` below, plus a fallback Vulkan ICD
# manifest in case the host doesn't provide one.
#
# SSH: same proven start.sh pattern as the COLMAP / LichtFeld images
# (custom RunPod images don't get SSH wired in automatically).

ARG COLMAP_BASE_IMAGE=dakord/oblaq-colmap-base:latest
ARG CUDA_VERSION=13.0.0

########################################
# Stage 1: pull COLMAP + its runtime closure out of oblaq-colmap-base
########################################
FROM ${COLMAP_BASE_IMAGE} AS colmap

# Copy every shared library COLMAP actually resolves, EXCEPT:
#  - glibc / libstdc++ / libgcc / libgomp: the 24.04 runtime's newer copies
#    are backward-compatible, and vendoring the older 22.04 ones would break
#    anything that needs the newer symbols.
#  - CUDA toolkit libs under /usr/local/cuda*: the CUDA 13.0 runtime base
#    image in stage 2 already has them (same version as colmap-base).
#  - the NVIDIA driver (libcuda, libnvidia-*) and GLVND GL dispatch libs:
#    mounted by the NVIDIA container runtime / installed from 24.04 apt.
# cuDSS gets its whole directory copied, since it can dlopen sibling libs
# that ldd doesn't see.
RUN set -eux; \
    mkdir -p /out/bin /out/lib; \
    cp -L /opt/colmap-install/bin/colmap /out/bin/colmap; \
    ldd /opt/colmap-install/bin/colmap | awk '/=> \//{print $3}' | sort -u > /tmp/libs.txt; \
    if ldd /opt/colmap-install/bin/colmap | grep -q "not found"; then \
        echo "colmap has unresolved libs inside colmap-base itself"; ldd /opt/colmap-install/bin/colmap; exit 1; fi; \
    grep -vE '/(libc|libm|libdl|libpthread|librt|libresolv|libutil|ld-linux-x86-64|libstdc\+\+|libgcc_s|libgomp)\.so' /tmp/libs.txt \
      | grep -vE '^/usr/local/cuda' \
      | grep -vE '/(libcuda|libnvidia-[^/]*|libGL|libGLX|libGLdispatch|libEGL|libOpenGL)\.so' \
      > /tmp/keep.txt; \
    xargs -a /tmp/keep.txt -I{} cp -L {} /out/lib/; \
    if [ -d /usr/lib/x86_64-linux-gnu/libcudss/13 ]; then cp -L /usr/lib/x86_64-linux-gnu/libcudss/13/*.so* /out/lib/ ; fi; \
    echo "vendored $(ls /out/lib | wc -l) libs for colmap"; ls /out/lib

########################################
# Stage 2: fetch the pinned Spirula release
########################################
FROM ubuntu:24.04 AS spirula

# Pinned on purpose (lesson from LichtFeld's floating LFS_REF=master): bump
# both values together when moving to a new release. Releases:
# https://github.com/harry7557558/spirula-studio/releases
ARG SPIRULA_VERSION=2026.9.24
ARG SPIRULA_SHA256=3560119e1d6ff91fa4bf49ed6a196f8b092db700e252f6288aa57a7568a65143

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*
RUN set -eux; \
    curl -fsSL -o /tmp/spirula.zip \
      "https://github.com/harry7557558/spirula-studio/releases/download/v${SPIRULA_VERSION}/spirula-${SPIRULA_VERSION}-ubuntu-vulkan-x86_64.zip"; \
    echo "${SPIRULA_SHA256}  /tmp/spirula.zip" | sha256sum -c -; \
    mkdir -p /opt/spirula; \
    unzip -q /tmp/spirula.zip -d /opt/spirula; \
    chmod +x /opt/spirula/spirula; \
    echo "${SPIRULA_VERSION}" > /opt/spirula/VERSION

########################################
# Stage 3: runtime
########################################
FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu24.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive
# `all` = compute,utility,graphics,video,display. `graphics` is what makes the
# runtime mount libGLX_nvidia / libnvidia-glvkspirv (the Vulkan driver);
# `video` lets spirula use Vulkan Video (VK_KHR_video_decode_queue) for
# GPU-decoding 360 video.
ENV NVIDIA_DRIVER_CAPABILITIES=all
ENV OMP_NUM_THREADS=64

# libvulkan1 / libopengl0 / libgomp1: spirula's actual dynamic deps (ldd).
#   libopengl0 is required even for CLI use - the binary links it for the GUI
#   code path and refuses to start without it.
# vulkan-tools: `vulkaninfo --summary` for diagnosing a pod that can't see
#   the GPU through Vulkan.
# ffmpeg: spirula shells out to `ffmpeg` to extract frames from video when
#   GPU decode isn't available.
# openssh-server, tmux, unzip, python3-pip+gdown, htop/nano/vim/wget: same
#   operational kit as the LichtFeld image (see that Dockerfile for the why).
RUN apt-get update && apt-get install -y --no-install-recommends \
        libvulkan1 vulkan-tools \
        libopengl0 libgl1 libglx0 libegl1 \
        libgomp1 \
        ffmpeg \
        openssh-server \
        tmux htop nano vim wget curl \
        zip unzip \
        python3 python3-pip \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install --no-cache-dir --break-system-packages gdown

# Fallback Vulkan ICD manifest for the NVIDIA driver. With the `graphics`
# capability, nvidia-container-toolkit normally mounts the host's own
# nvidia_icd.json over this path; if the host doesn't ship one (some
# datacenter installs don't), the loader still finds the driver via this.
RUN mkdir -p /etc/vulkan/icd.d && printf '%s\n' \
    '{' \
    '    "file_format_version" : "1.0.0",' \
    '    "ICD": {' \
    '        "library_path": "libGLX_nvidia.so.0",' \
    '        "api_version" : "1.3.0"' \
    '    }' \
    '}' > /etc/vulkan/icd.d/nvidia_icd.json

# --- Spirula ---
COPY --from=spirula /opt/spirula /opt/spirula
RUN ln -s /opt/spirula/spirula /usr/local/bin/spirula \
    && spirula --help > /dev/null \
    && echo "spirula $(cat /opt/spirula/VERSION) OK"

# --- COLMAP (from oblaq-colmap-base) ---
COPY --from=colmap /out/bin/colmap /opt/colmap/bin/colmap
COPY --from=colmap /out/lib/ /opt/colmap/lib/
COPY colmap-wrapper.sh /usr/local/bin/colmap
RUN chmod +x /usr/local/bin/colmap \
    && if LD_LIBRARY_PATH=/opt/colmap/lib ldd /opt/colmap/bin/colmap | grep "not found"; then \
         echo "COLMAP is missing libs on 24.04 - see above"; exit 1; fi \
    && colmap -h | grep -q "with CUDA" \
    || (echo "COLMAP not runnable or built WITHOUT CUDA" && exit 1)

# Spirula's built-in web viewer (spirula train ... --viewer-port, default
# 7007). Reach it with `ssh -L 7007:localhost:7007 root@<pod> -p <port>`, or
# expose 7007 as an HTTP port in the RunPod template to get a proxy URL.
EXPOSE 7007

# --- SSH setup (build-time config; runtime key injection happens in start.sh) ---
RUN mkdir -p /var/run/sshd /root/.ssh && chmod 700 /root/.ssh \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

COPY start.sh /root/start.sh
RUN chmod +x /root/start.sh

WORKDIR /root
ENTRYPOINT ["/root/start.sh"]
