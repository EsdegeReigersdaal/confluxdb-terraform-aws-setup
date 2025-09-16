# Build your Dagster Cloud agent image extending the official image.
# Use a specific tag for reproducibility (example shown uses latest; pin in prod).
FROM ghcr.io/dagster-io/dagster-cloud-agent:latest

# Copy instance config to a known path inside the image
COPY dagster.yaml /opt/dagster/app/dagster.yaml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Wrap the base command to ensure dagster.yaml is available in DAGSTER_HOME
# before launching the agent. We preserve the base image's default CMD by exec "$@".
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
