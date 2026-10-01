#!/usr/bin/env bash

# Stop immediately if a command fails, a variable is missing,
# or a command in a pipeline fails.
set -euo pipefail

# Confirm that the files required by the container exist.
test -s app/index.html
test -s app/healthz

# Confirm that the page includes the expected application identity and version.
grep -q "Kubernetes CI/CD Lab" app/index.html
grep -q "Version 1.1.0" app/index.html

# Remove newline characters before comparing the health response.
health_response="$(tr -d '\r\n' < app/healthz)"
test "$health_response" = "healthy"

echo "Static application tests passed."
