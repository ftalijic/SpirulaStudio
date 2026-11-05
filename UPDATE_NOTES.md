# Spirula Studio 2026.9.24 -> 2026.10.30 (RunPod image)

Checked 2026-11-05: v2026.10.30 (released 2026-10-30) is still the latest.
Checksum of spirula-2026.10.30-ubuntu-vulkan-x86_64.zip was verified against
the GitHub release digest: 19e9fdab...ad5a2. The zip layout is unchanged
(`spirula` binary at the zip root).

## Apply
1. Copy Dockerfile, build-image.yml and README.md over the files in the
   GitHub repo. build-image.yml goes to .github/workflows/. Or run
   `git apply v2026.10.30.patch`, after moving the workflow path in the patch
   if you need to.
2. Push to main. The Action builds and pushes dakord/spirula-studio:latest
   plus a run-number tag. To keep a rollback, note the current run-number tag
   (9.24) before pushing.

## Verify on the first pod
    cat /opt/spirula/VERSION                   # 2026.10.30
    cat /root/vulkan-check.log; spirula sam devices; colmap -h | head -3
    spirula train --help-all > /workspace/spirula_train_help_2026.10.30.txt
Diff that help output against the saved 2026.9.30 help file, and check every
flag in Guides/Spirula_Quality_Flags.md still exists. Then re-run one known
scene (KRK VID_001) before trusting old flag values: 10.6 and 10.30 both change
training quality.

## Not covered here
- Local spirula.exe is still 2026.9.30. Windows zip:
  spirula-2026.10.30-windows-vulkan-x86_64.zip
  (sha256 dfaf1376ab78acf4bfbaaeb7a3f12b7c06ab30bf1d9eee6082100dbc1e7b71dd)
