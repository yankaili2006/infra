job "orchestrator" {
  datacenters = ["dc1"]
  type        = "system"  # 每个client节点一个（dev模式只有1个节点）
  priority    = 90
  node_pool = "local-dev"  # 匹配节点的 pool

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
        args    = ["/mnt/data1/pcloud/infra/local-deploy/scripts/start-orchestrator.sh"]
      }

      env {
        NODE_ID     = "primihub"  # 直接使用节点名称，避免模板变量问题
        ENVIRONMENT = "local"

        # 存储配置（使用本地文件系统）
        STORAGE_PROVIDER            = "Local"
        ARTIFACTS_REGISTRY_PROVIDER = "Local"
        TEMPLATE_BUCKET_NAME        = "local-templates"

        # 路径配置由 start-orchestrator.sh 脚本从环境变量加载
        # 脚本会读取 config/env.sh 中的 PCLOUD_HOME 和 E2B_STORAGE_PATH

        # 网络配置
        ALLOW_SANDBOX_INTERNET = "true"

        # 基础设施连接
        POSTGRES_CONNECTION_STRING   = "postgresql://postgres:postgres@127.0.0.1:5432/e2b?sslmode=disable"
        REDIS_URL                    = "127.0.0.1:6379"
        CLICKHOUSE_CONNECTION_STRING = "clickhouse://clickhouse:clickhouse@127.0.0.1:9000/clickhouse"
        OTEL_COLLECTOR_GRPC_ENDPOINT = "127.0.0.1:4317"
        LOGS_COLLECTOR_ADDRESS       = "http://127.0.0.1:30006"

        # 端口配置
        GRPC_PORT  = "5008"
        PROXY_PORT = "5007"

        # 服务列表 - 移除template-manager，让其独立运行
        ORCHESTRATOR_SERVICES = "orchestrator"

        # 超时配置（冷启动需要更长时间）
        ENVD_TIMEOUT = "60s"

        # 禁用外部服务
        LAUNCH_DARKLY_API_KEY = ""

        # GIN模式
        GIN_MODE = "release"

        # 禁用 Huge Pages（使用 4KB 标准页面进行冷启动测试）
        ORCHESTRATOR_HUGE_PAGES = "false"
        HUGE_PAGES = "false"
      }

      resources {
        cpu    = 4000  # 4 CPU (提高以支持更多并发VM)
        memory = 8192  # 8GB (提高以支持VM缓存)

        # 内存保留（确保有足够内存用于VM创建）
        memory_max = 16384  # 最大16GB
      }

      # Firecracker需要sudo权限
      # 注意：需要配置sudo免密码或使用capabilities
      # sudo setcap cap_net_admin,cap_sys_admin+ep /path/to/orchestrator
    }
  }
}
