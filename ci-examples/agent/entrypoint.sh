#!/bin/sh
set -euo pipefail

HOME_DIR="${DAGSTER_HOME:-/dagster_home}"
mkdir -p "$HOME_DIR"

# Copy baked instance config into DAGSTER_HOME so the agent can read it
cp -f /opt/dagster/app/dagster.yaml "$HOME_DIR/dagster.yaml"

# Chain to the base image's default CMD
exec "$@"

