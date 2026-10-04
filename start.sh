#!/bin/bash
# Runs at container START (not build time) - same SSH pattern as the COLMAP
# and LichtFeld images: $PUBLIC_KEY is only set when the pod launches.

# Generate host keys if they don't exist yet (first boot of this container)
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -A
fi

# Write the pod's authorized public key, if RunPod provided one
if [ -n "$PUBLIC_KEY" ]; then
    echo "$PUBLIC_KEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi

# Spirula downloads SAM / MoGe / Metric3D checkpoints on first use into
# $XDG_CACHE_HOME. Point that at the network volume so they survive pod
# restarts instead of re-downloading into the ephemeral container disk.
# Written to .bashrc because SSH sessions don't inherit the container's env.
if [ -d /workspace ]; then
    mkdir -p /workspace/.cache
    grep -q 'XDG_CACHE_HOME=/workspace/.cache' /root/.bashrc 2>/dev/null \
        || echo 'export XDG_CACHE_HOME=/workspace/.cache' >> /root/.bashrc
fi

# Record whether Vulkan can see the GPU - the first thing to check if
# spirula says "no Vulkan devices were found".
{
    echo "=== $(date) ==="
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>&1
    vulkaninfo --summary 2>&1 | grep -E 'deviceName|apiVersion|driverVersion|ERROR'
} > /root/vulkan-check.log 2>&1

# Start sshd in the background
service ssh start

# Keep the container running
tail -f /dev/null
