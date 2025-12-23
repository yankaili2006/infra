job "api" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 90
  node_pool   = "local-dev"  # 匹配节点的 pool

  # 本地开发只需要1个实例
  group "api-service" {
    count = 1

    restart {
      attempts = 3
      delay    = "15s"
      interval = "1m"
      mode     = "delay"
    }

    network {
      mode = "host"
      port "http" {
        static = 3000
      }
    }

    # Consul服务注册
    service {
      name = "api"
      port = "http"

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }
    }

    # 数据库迁移任务（prestart）- 暂时禁用
    # task "db-migrator" {
    #   driver = "docker"
    #
    #   lifecycle {
    #     hook    = "prestart"
    #     sidecar = false
    #   }
    #
    #   config {
    #     image = "e2b-db-migrator:local"  # 本地构建的镜像
    #     force_pull = false  # 使用本地镜像，不从远程拉取
    #
    #     # 使用host网络以便访问localhost的数据库
    #     network_mode = "host"
    #   }
    #
    #   env {
    #     POSTGRES_CONNECTION_STRING = "postgres://postgres:postgres@127.0.0.1:5432/postgres?sslmode=disable"
    #   }
    #
    #   resources {
    #     cpu    = 250
    #     memory = 128
    #   }
    # }

    # API主任务
    task "api" {
      driver = "raw_exec"

      config {
        command = "/home/primihub/pcloud/infra/packages/api/bin/api"
        args     = ["--port", "3000"]
      }

      # 环境变量
      env {
        NODE_ID     = "${node.unique.id}"
        ENVIRONMENT = "development"

        # 数据库连接
        POSTGRES_CONNECTION_STRING   = "postgres://postgres:postgres@127.0.0.1:5432/postgres?sslmode=disable&connect_timeout=30"
        CLICKHOUSE_CONNECTION_STRING = "clickhouse://clickhouse:clickhouse@127.0.0.1:9000/clickhouse"

        # Redis
        REDIS_URL         = "127.0.0.1:6379"
        REDIS_CLUSTER_URL = ""
        REDIS_TLS_CA_BASE64 = ""

        # 可观测性
        OTEL_COLLECTOR_GRPC_ENDPOINT = "127.0.0.1:4317"
        LOGS_COLLECTOR_ADDRESS       = "http://127.0.0.1:30006"
        OTEL_TRACING_PRINT           = "false"

        # Nomad（dev模式不需要token）
        NOMAD_TOKEN = ""

        # 本地开发使用静态服务发现
        ORCHESTRATOR_PORT = "5008"

        # 本地cluster配置
        LOCAL_CLUSTER_ENDPOINT = "127.0.0.1:3001"
        LOCAL_CLUSTER_TOKEN    = "--edge-secret--"

        # 禁用外部服务
        POSTHOG_API_KEY               = ""
        ANALYTICS_COLLECTOR_HOST      = ""
        ANALYTICS_COLLECTOR_API_TOKEN = ""
        LAUNCH_DARKLY_API_KEY         = ""

        # 测试用密钥
        ADMIN_TOKEN                    = "local-admin-token"
        SANDBOX_ACCESS_TOKEN_HASH_SEED = "--sandbox-access-token-hash-seed--"
        SUPABASE_JWT_SECRETS           = "test-jwt-secret"

        # 模板bucket（本地不需要但代码可能需要）
        TEMPLATE_BUCKET_NAME = "skip"

        # 存储配置（使用本地文件系统）
        STORAGE_PROVIDER            = "Local"
        ARTIFACTS_REGISTRY_PROVIDER = "Local"
        LOCAL_TEMPLATE_STORAGE_BASE_PATH = "/home/primihub/e2b-storage/e2b-template-storage"
        BUILD_CACHE_BUCKET_NAME    = "/home/primihub/e2b-storage/e2b-build-cache"
        TEMPLATE_CACHE_DIR         = "/home/primihub/e2b-storage/e2b-template-cache"

        # 默认版本
        DEFAULT_KERNEL_VERSION      = "vmlinux-6.1.158"
        DEFAULT_FIRECRACKER_VERSION = "v1.12.1_d990331"
      }

      resources {
        cpu    = 1000  # 1 CPU
        memory = 2048  # 2GB
      }
    }
  }
}
