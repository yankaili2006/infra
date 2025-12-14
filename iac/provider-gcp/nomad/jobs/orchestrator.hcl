job "orchestrator-${latest_orchestrator_job_id}" {
  type = "system"
  node_pool = "${node_pool}"

  priority = 90

  group "client-orchestrator" {
    service {
      name = "orchestrator"
      port = "${port}"

      provider = "nomad"

      check {
        type         = "http"
        path         = "/health"
        name         = "health"
        interval     = "20s"
        timeout      = "5s"
      }
    }

    service {
      name = "orchestrator-proxy"
      port = "${proxy_port}"

      provider = "nomad"

      check {
        type     = "tcp"
        name     = "health"
        interval = "30s"
        timeout  = "1s"
      }
    }

    task "check-placement" {
      driver = "raw_exec"

      lifecycle {
        hook = "prestart"
        sidecar = false
      }

      restart {
        attempts = 0
      }

      template {
        destination = "local/check-placement.sh"
        data = <<EOT
#!/bin/bash

if [ "{{with nomadVar "nomad/jobs" }}{{ .latest_orchestrator_job_id }}{{ end }}" != "${latest_orchestrator_job_id}" ]; then
  echo "This orchestrator is not the latest version, exiting"
  exit 1
fi
EOT
      }

      config {
        command = "local/check-placement.sh"
      }
    }

    # Cleanup orphaned network namespaces before starting orchestrator
    task "cleanup-network" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      restart {
        attempts = 0
      }

      template {
        destination = "local/cleanup-network.sh"
        data = <<EOT
#!/bin/bash
# Cleanup orphaned network namespaces from previous orchestrator runs

echo "Cleaning up orphaned network namespaces..."

# Count initial state
INITIAL_NETNS=$(ip netns list 2>/dev/null | grep -c "^ns-" || echo "0")
echo "Found $INITIAL_NETNS orphaned namespaces"

if [ "$INITIAL_NETNS" -eq 0 ]; then
  echo "No orphaned namespaces to clean"
  exit 0
fi

# Unmount and delete all ns-* namespaces
CLEANED=0
for ns in $(ip netns list 2>/dev/null | grep "^ns-" | awk '{print $1}'); do
  umount "/run/netns/$ns" 2>/dev/null || true
  rm -f "/run/netns/$ns" 2>/dev/null && CLEANED=$((CLEANED + 1))
done

# Clean up orphaned veth devices
VETHS=$(ip link show 2>/dev/null | grep -o "^[0-9]*: veth[^@:]*" | awk '{print $2}' || echo "")
VETH_COUNT=0
for veth in $VETHS; do
  if [ -n "$veth" ]; then
    ip link delete "$veth" 2>/dev/null && VETH_COUNT=$((VETH_COUNT + 1))
  fi
done

echo "Cleanup complete: removed $CLEANED namespaces and $VETH_COUNT veth devices"
EOT
      }

      config {
        command = "/bin/bash"
        args    = ["local/cleanup-network.sh"]
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    task "start" {
      driver = "raw_exec"

      restart {
        attempts = 0
      }

      env {
        NODE_ID                      = "$${node.unique.name}"
        CONSUL_TOKEN                 = "${consul_acl_token}"
        OTEL_TRACING_PRINT           = "${otel_tracing_print}"
        LOGS_COLLECTOR_ADDRESS       = "${logs_collector_address}"
        ENVIRONMENT                  = "${environment}"
        ENVD_TIMEOUT                 = "${envd_timeout}"
        TEMPLATE_BUCKET_NAME         = "${template_bucket_name}"
        OTEL_COLLECTOR_GRPC_ENDPOINT = "${otel_collector_grpc_endpoint}"
        ALLOW_SANDBOX_INTERNET       = "${allow_sandbox_internet}"
        SHARED_CHUNK_CACHE_PATH      = "${shared_chunk_cache_path}"
        CLICKHOUSE_CONNECTION_STRING = "${clickhouse_connection_string}"
        REDIS_URL                    = "${redis_url}"
        REDIS_CLUSTER_URL            = "${redis_cluster_url}"
        REDIS_TLS_CA_BASE64          = "${redis_tls_ca_base64}"
        GRPC_PORT                    = "${port}"
        PROXY_PORT                   = "${proxy_port}"
        GIN_MODE                     = "release"

%{ if launch_darkly_api_key != "" }
        LAUNCH_DARKLY_API_KEY         = "${launch_darkly_api_key}"
%{ endif }
      }

      config {
        command = "/bin/bash"
        args    = ["-c", " chmod +x local/orchestrator && local/orchestrator"]
      }

      artifact {
        %{ if environment == "dev" }
        // Version hash is only available for dev to increase development speed in prod use rolling updates
        source      = "gcs::https://www.googleapis.com/storage/v1/${bucket_name}/orchestrator?version=${orchestrator_checksum}"
        %{ else }
        source      = "gcs::https://www.googleapis.com/storage/v1/${bucket_name}/orchestrator"
        %{ endif }
      }
    }
  }
}
