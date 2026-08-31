#!/bin/bash
#
# Runs one real-time ScribeKit soak. Developer tooling: nothing here is part of
# the shipping application, and nothing runs unless this script is invoked.
#
# Usage:
#   Tools/SoakValidation/run-soak.sh sustainedCapture [minutes] [bundle-id]
#   Tools/SoakValidation/run-soak.sh presentationCost [minutes] [bundle-id]
#   Tools/SoakValidation/run-soak.sh pausedBaseline   [minutes] [bundle-id]
#
# `minutes` is the total capture length; the presentation and pause runs split
# it into three equal phases. The default is 60.
#
# The build is Release with ENABLE_TESTABILITY=YES: optimisation is the
# shipping one, and `-enable-testing` is only what lets the harness link
# against the module it is measuring.
#
# The run is requested through a file inside the application's sandbox
# container, because `xcodebuild` does not carry its own environment into a
# Release-configured test host. The file is written here and removed when the
# script exits, so a soak cannot start without this script having run.

set -euo pipefail

CASE="${1:-sustainedCapture}"
MINUTES="${2:-60}"
SOURCE="${3:-}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONTAINER="$HOME/Library/Containers/quang.ScribeKit/Data"
RUN_FILE="$CONTAINER/.scribekit-soak-run"

mkdir -p "$CONTAINER"
cat > "$RUN_FILE" <<EOF
SCRIBEKIT_SOAK=1
SCRIBEKIT_SOAK_MINUTES=$MINUTES
SCRIBEKIT_SOAK_SOURCE=$SOURCE
SCRIBEKIT_SOAK_RETENTION=${SCRIBEKIT_SOAK_RETENTION:-compressed}
SCRIBEKIT_SOAK_SAMPLE_SECONDS=${SCRIBEKIT_SOAK_SAMPLE_SECONDS:-300}
${SCRIBEKIT_SOAK_OUTPUT:+SCRIBEKIT_SOAK_OUTPUT=$SCRIBEKIT_SOAK_OUTPUT}
EOF
trap 'rm -f "$RUN_FILE"' EXIT

echo "ScribeKit soak: $CASE for $MINUTES minutes"
echo "Requested through: $RUN_FILE"
echo "Artifacts default to the sandbox container's own temporary directory;"
echo "the run prints the exact path before it starts."
echo

cd "$ROOT"
xcodebuild \
  -project ScribeKit.xcodeproj \
  -scheme ScribeKit \
  -configuration Release \
  -destination 'platform=macOS' \
  -only-testing:"ScribeKitTests/SoakValidationTests/$CASE()" \
  ENABLE_TESTABILITY=YES \
  test
