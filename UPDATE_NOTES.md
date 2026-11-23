# Spirula Studio 2026.10.30 -> 2026.11.12 (RunPod image)

Checked 2026-11-23: v2026.11.12 (released 2026-11-12) is the latest.
SHA-256 of spirula-2026.11.12-ubuntu-vulkan-x86_64.zip is the GitHub release
digest (read from the GitHub API twice, same value both times). The Docker
build re-checks it with `sha256sum -c`, so a wrong value fails the build.
Zip layout (`spirula` binary at the zip root) not verified; the Dockerfile's
`spirula --help` step fails the build if it changed.

## Verify on the first pod
    cat /opt/spirula/VERSION                   # 2026.11.12
    cat /root/vulkan-check.log; spirula sam devices; colmap -h | head -3
    spirula train --help-all > /workspace/spirula_train_help_2026.11.12.txt
Check: `--calib-correction` (off|basic|accurate) and `--calib-warp-grid` exist;
`--floater-suppression` now takes mild|moderate|strong (old strong = moderate);
distraction robustness moved to advanced options (`--help-all | grep distraction`).
Release notes say training quality changes on purpose: re-run a known scene
before trusting old flag values.

## Rollback
The previous image (10.30) keeps its run-number tag on Docker Hub
(dakord/spirula-studio:<run number>); check the Actions history for it.
