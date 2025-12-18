#!/bin/bash
set -euo pipefail

latest_version=$(ls packages/db/migrations/ | sed 's/_.*//' | sort -n | tail -n 1)
echo "$latest_version"