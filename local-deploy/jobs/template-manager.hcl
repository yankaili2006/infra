job "template-manager" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 90
  node_pool   = "local-dev"

  group "template-manager" {
    count = 1

    restart {
      attempts = 3
      delay    = "15s"
      interval = "1m"
      mode     = "delay"
    }

    network {
      port "grpc" {
        static = 5009
      }
    }

    # Consul服务注册
    service {
      name = "template-manager"
      port = "grpc"

      check {
        type     = "http"
        path     = "/health"
        interval = "20s"
        timeout  = "5s"
      }
    }

    task "template-manager" {
      driver = "raw_exec"

      config {
        command = "/mnt/sdb/pcloud/infra/packages/orchestrator/bin/orchestrator"
        args    = ["--service", "template-manager"]
      }

      env {
        NODE_ID     = "${node.unique.name}"
        ENVIRONMENT = "local"

        # 存储配置（使用本地文件系统）
        STORAGE_PROVIDER            = "Local"
        ARTIFACTS_REGISTRY_PROVIDER = "Local"

        # 确保使用本地存储，不尝试连接GCP
        GOOGLE_APPLICATION_CREDENTIALS = ""
        GCP_PROJECT_ID = ""
        GCP_REGION = ""

        # 本地路径配置
        FIRECRACKER_VERSIONS_DIR = "/mnt/sdb/pcloud/infra/packages/fc-versions/builds"
        HOST_ENVD_PATH           = "/mnt/sdb/pcloud/infra/packages/envd/bin/envd"
        HOST_KERNELS_DIR         = "/mnt/sdb/pcloud/infra/packages/fc-kernels"
        ORCHESTRATOR_BASE_PATH   = "/mnt/sdb/e2b-storage/e2b-orchestrator"
        SANDBOX_DIR              = "/mnt/sdb/e2b-storage/e2b-fc-vm"

        # 缓存目录（与orchestrator共享）
        LOCAL_TEMPLATE_STORAGE_BASE_PATH = "/mnt/sdb/e2b-storage/e2b-template-storage"
        SANDBOX_CACHE_DIR                = "/mnt/sdb/e2b-storage/e2b-sandbox-cache"
        SNAPSHOT_CACHE_DIR               = "/mnt/sdb/e2b-storage/e2b-snapshot-cache"
        TEMPLATE_CACHE_DIR               = "/mnt/sdb/e2b-storage/e2b-template-cache"
        SHARED_CHUNK_CACHE_PATH          = "/mnt/sdb/e2b-storage/e2b-chunk-cache"

        # 模板构建专用配置
        TEMPLATE_BUCKET_NAME       = "/mnt/sdb/e2b-storage/e2b-template-storage"
        BUILD_CACHE_BUCKET_NAME    = "/mnt/sdb/e2b-storage/e2b-build-cache"
        DOCKERHUB_REMOTE_REPOSITORY_URL = "registry.hub.docker.com"

        # 基础设施连接
        REDIS_URL                    = "127.0.0.1:6379"
        CLICKHOUSE_CONNECTION_STRING = "clickhouse://clickhouse:clickhouse@127.0.0.1:9000/clickhouse"
        OTEL_COLLECTOR_GRPC_ENDPOINT = "127.0.0.1:4317"
        LOGS_COLLECTOR_ADDRESS       = "http://127.0.0.1:30006"

        # 端口配置
        GRPC_PORT = "5009"
        PROXY_PORT = "5012"
        HYPERLOOP_PROXY_PORT = "5011"

        # Template Manager specific config
        HYPERLOOP_SERVER_PORT = "5011"  # 保留此项以防万一

        # 服务标识
        ORCHESTRATOR_SERVICES = "template-manager"

        # 超时配置
        ENVD_TIMEOUT = "10s"

        # 禁用外部服务
        LAUNCH_DARKLY_API_KEY = ""

        # GIN模式
        GIN_MODE = "release"

        # 默认版本
        DEFAULT_KERNEL_VERSION      = "vmlinux-6.1.158"
        DEFAULT_FIRECRACKER_VERSION = "v1.12.1_d990331"
      }

      resources {
        cpu    = 1000  # 1 CPU
        memory = 2048  # 2GB
      }

      # Template Manager也可能需要构建容器，需要Docker访问权限
      # 如果使用Docker构建模板，可能需要额外权限配置
    }
  }
}
