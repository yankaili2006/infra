job "client-proxy" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 90
  node_pool   = "local-dev"

  # 本地开发只需要1个实例
  group "client-proxy" {
    count = 1

    restart {
      attempts = 3
      delay    = "15s"
      interval = "1m"
      mode     = "delay"
    }

    network {
      port "http" {
        static = 3002
      }
    }

    # Consul服务注册
    service {
      name = "client-proxy"
      port = "http"

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "client-proxy" {
      driver = "raw_exec"

      config {
        command = "/mnt/sdb/pcloud/infra/packages/client-proxy/bin/client-proxy"
        args = [
          "--port", "3002",
        ]
      }

      # 环境变量
      env {
        NODE_ID     = "${node.unique.id}"
        NODE_IP     = "127.0.0.1"
        ENVIRONMENT = "local"

        # 服务端口
        PORT = "3002"

        # Redis配置
        REDIS_URL         = "127.0.0.1:6379"
        REDIS_CLUSTER_URL = ""
        REDIS_TLS_CA_BASE64 = ""

        # Consul配置
        CONSUL_ADDRESS = "127.0.0.1:8500"
        CONSUL_TOKEN   = ""

        # 可观测性
        OTEL_COLLECTOR_GRPC_ENDPOINT = "127.0.0.1:4317"
        LOGS_COLLECTOR_ADDRESS       = "http://127.0.0.1:30006"
        OTEL_TRACING_PRINT           = "false"

        # 本地开发使用Nomad服务发现（Nomad通过Consul进行服务发现）
        # Client-Proxy通过Nomad+Consul发现orchestrator实例
        ORCHESTRATOR_SERVICE_NAME = "orchestrator"
        SD_ORCHESTRATOR_PROVIDER = "NOMAD"

        # Nomad配置
        SD_ORCHESTRATOR_NOMAD_ENDPOINT = "http://127.0.0.1:4646"
        SD_ORCHESTRATOR_NOMAD_TOKEN = "local-dev-no-acl"  # Dev mode无需真实token，但代码要求非空
        SD_ORCHESTRATOR_NOMAD_JOB_PREFIX = "orchestrator"  # orchestrator job的名称

        # Loki日志收集器配置 (本地开发可选)
        LOKI_URL = "http://127.0.0.1:3100"

        # 禁用外部服务
        POSTHOG_API_KEY               = ""
        ANALYTICS_COLLECTOR_HOST      = ""
        ANALYTICS_COLLECTOR_API_TOKEN = ""
        LAUNCH_DARKLY_API_KEY         = ""

        # API连接配置（用于路由验证）
        API_URL = "http://127.0.0.1:3000"

        # Edge API认证密钥（必须与API中的LOCAL_CLUSTER_TOKEN匹配）
        EDGE_SECRET = "--edge-secret--"

        # 超时配置
        REQUEST_TIMEOUT = "30s"

        # 健康检查配置（本地开发可以放宽）
        HEALTH_CHECK_INTERVAL      = "10s"
        SKIP_HEALTH_CHECK_ON_START = "true"

        # GIN模式
        GIN_MODE = "release"
      }

      resources {
        cpu    = 500   # 0.5 CPU
        memory = 1024  # 1GB
      }
    }
  }
}
