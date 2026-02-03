#!/bin/bash
PCLOUD_HOME="${PCLOUD_HOME:-/home/primihub/pcloud}"
exec sudo -E "$PCLOUD_HOME/infra/packages/orchestrator/bin/orchestrator" "$@"
