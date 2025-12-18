job "orchestrator" {
  datacenters = ["dc1"]
  type        = "system"  # 每个client节点一个（dev模式只有1个节点）
  priority    = 90
  node_pool   = "default"

  group "orchestrator" {

    network {
      mode = "host"  # 使用宿主机网络，避免网络隔离问题
      port "grpc" {
        static = 5008
      }
      port "proxy" {
        static = 5007
      }
    }

    service {
      name = "orchestrator"
      port = "grpc"

      check {
        type     = "http"
        path     = "/health"
        interval = "20s"
        timeout  = "5s"
      }
    }

    service {
      name = "orchestrator-proxy"
      port = "proxy"

      check {
        type     = "tcp"
        interval = "30s"
        timeout  = "1s"
      }
    }

    task "orchestrator" {
      driver = "raw_exec"  # 需要直接访问系统资源

      config {
        command = "sudo"
        args    = ["-E", "/mnt/sdb/pcloud/infra/packages/orchestrator/bin/orchestrator"]
      }

      env {
        NODE_ID     = "${node.unique.name}"
        ENVIRONMENT = "local"

        # 存储配置（使用本地文件系统）
        STORAGE_PROVIDER            = "Local"
        ARTIFACTS_REGISTRY_PROVIDER = "Local"

        # 本地路径配置
        FIRECRACKER_VERSIONS_DIR = "/mnt/sdb/pcloud/infra/packages/fc-versions/builds"
        HOST_ENVD_PATH           = "/mnt/sdb/pcloud/infra/packages/envd/bin/envd"
        HOST_KERNELS_DIR         = "/mnt/sdb/pcloud/infra/packages/fc-kernels"
        ORCHESTRATOR_BASE_PATH   = "/mnt/sdb/e2b-storage/e2b-orchestrator"
        SANDBOX_DIR              = "/mnt/sdb/e2b-storage/e2b-fc-vm"

        # 缓存目录
        LOCAL_TEMPLATE_STORAGE_BASE_PATH = "/mnt/sdb/e2b-storage/e2b-template-storage"
        BUILD_CACHE_BUCKET_NAME          = "/mnt/sdb/e2b-storage/e2b-build-cache"
        SANDBOX_CACHE_DIR                = "/mnt/sdb/e2b-storage/e2b-sandbox-cache"
        SNAPSHOT_CACHE_DIR               = "/mnt/sdb/e2b-storage/e2b-snapshot-cache"
        TEMPLATE_CACHE_DIR               = "/mnt/sdb/e2b-storage/e2b-template-cache"
        SHARED_CHUNK_CACHE_PATH          = "/mnt/sdb/e2b-storage/e2b-chunk-cache"

        # 锁文件
        ORCHESTRATOR_LOCK_PATH = "/mnt/sdb/e2b-storage/e2b-orchestrator.lock"

        # 网络配置
        ALLOW_SANDBOX_INTERNET = "true"

        # 基础设施连接
        REDIS_URL                    = "127.0.0.1:6379"
        CLICKHOUSE_CONNECTION_STRING = "clickhouse://clickhouse:clickhouse@127.0.0.1:9000/clickhouse"
        OTEL_COLLECTOR_GRPC_ENDPOINT = "127.0.0.1:4317"
        LOGS_COLLECTOR_ADDRESS       = "http://127.0.0.1:30006"

        # 端口配置
        GRPC_PORT  = "5008"
        PROXY_PORT = "5007"

        # 服务列表 - 移除template-manager，让其独立运行
        ORCHESTRATOR_SERVICES = "orchestrator"

        # 超时配置
        ENVD_TIMEOUT = "10s"

        # 禁用外部服务
        LAUNCH_DARKLY_API_KEY = ""

        # GIN模式
        GIN_MODE = "release"
      }

      resources {
        cpu    = 2000  # 2 CPU
        memory = 4096  # 4GB
      }

      # Firecracker需要sudo权限
      # 注意：需要配置sudo免密码或使用capabilities
      # sudo setcap cap_net_admin,cap_sys_admin+ep /path/to/orchestrator
    }
  }
}
