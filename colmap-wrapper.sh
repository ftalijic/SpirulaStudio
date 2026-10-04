#!/bin/bash
# Installed as /usr/local/bin/colmap.
#
# The real binary at /opt/colmap/bin/colmap was built on Ubuntu 22.04
# (dakord/oblaq-colmap-base) and runs here against its own vendored .so set
# in /opt/colmap/lib. Those libs are put on LD_LIBRARY_PATH ONLY for this
# process, so the older 22.04 libraries never shadow the 24.04 system ones
# that spirula (and everything else on the pod) relies on.
export LD_LIBRARY_PATH="/opt/colmap/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
# Qt is linked in but never needed for CLI use; stop it looking for a display.
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
exec /opt/colmap/bin/colmap "$@"
