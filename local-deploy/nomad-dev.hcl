# Nomad Dev 模式配置
# 单节点本地开发环境

# 数据目录
data_dir = "/tmp/nomad-local"

# 日志配置
log_level = "INFO"
log_json  = false

# 地址绑定（0.0.0.0 允许外部访问）
bind_addr = "0.0.0.0"

# 服务器配置（dev模式同时是server和client）
server {
  enabled          = true
  bootstrap_expect = 1
}

# 客户端配置
client {
  enabled = true

  # 节点池
  node_pool = "local-dev"

  # 预留资源（根据本机资源调整）
  reserved {
    cpu    = 1000  # 预留1个核心给系统
    memory = 2048  # 预留2GB给系统
  }
}

# 插件配置
plugin "raw_exec" {
  config {
    enabled = true
  }
}

plugin "docker" {
  config {
    # 允许挂载卷
    volumes {
      enabled = true
    }

    # 不允许特权容器（安全考虑）
    allow_privileged = false
  }
}

# 遥测配置
telemetry {
  disable_hostname              = true
  prometheus_metrics            = true
  publish_allocation_metrics    = true
  publish_node_metrics          = true
  collection_interval           = "5s"
}

# ACL配置（dev模式禁用）
acl {
  enabled = false
}

# Consul集成
consul {
  address          = "127.0.0.1:8500"
  auto_advertise   = true
  server_auto_join = true
  client_auto_join = true
}

# 地址广播
advertise {
  http = "127.0.0.1"
  rpc  = "127.0.0.1"
  serf = "127.0.0.1"
}

# 端口配置
ports {
  http = 4646
  rpc  = 4647
  serf = 4648
}
