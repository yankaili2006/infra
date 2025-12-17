#!/bin/bash
# E2B管理脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2B_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$E2B_DIR/config"

# 加载环境变量
if [ -f "$CONFIG_DIR/.env.e2b" ]; then
    source "$CONFIG_DIR/.env.e2b"
elif [ -f "$CONFIG_DIR/.env.e2b.example" ]; then
    echo "警告: 使用示例配置文件，请复制 .env.e2b.example 为 .env.e2b 并修改配置"
    source "$CONFIG_DIR/.env.e2b.example"
fi

# Docker Compose文件
COMPOSE_FILE="$CONFIG_DIR/docker-compose.e2b.yml"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
    echo "E2B管理脚本"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  start          启动E2B服务"
    echo "  stop           停止E2B服务"
    echo "  restart        重启E2B服务"
    echo "  status         查看服务状态"
    echo "  logs [服务]    查看日志 (默认: 所有服务)"
    echo "  backup         备份数据"
    echo "  restore [文件] 恢复备份"
    echo "  cleanup        清理缓存和临时文件"
    echo "  health         健康检查"
    echo "  init           初始化配置"
    echo "  update         更新E2B镜像"
    echo "  help           显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 start        # 启动所有服务"
    echo "  $0 logs e2b-api # 查看API服务日志"
    echo "  $0 backup       # 备份数据"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}错误: Docker未安装${NC}"
        exit 1
    fi
    
    if ! systemctl is-active --quiet docker; then
        echo "启动Docker服务..."
        sudo systemctl start docker
    fi
}

check_compose() {
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}错误: Docker Compose未安装${NC}"
        exit 1
    fi
}

start_services() {
    check_docker
    check_compose
    
    echo "启动E2B服务..."
    docker-compose -f "$COMPOSE_FILE" up -d
    
    echo -e "${GREEN}服务启动完成${NC}"
    echo ""
    echo "访问地址:"
    echo "  - E2B API:      http://localhost:${E2B_API_PORT:-3000}"
    echo "  - 健康检查:     http://localhost:${E2B_API_PORT:-3000}/health"
    echo "  - Client Proxy: http://localhost:${E2B_CLIENT_PROXY_PORT:-3002}"
    echo "  - Grafana:      http://localhost:${GRAFANA_PORT:-3001} (admin/${GRAFANA_ADMIN_PASSWORD:-admin})"
}

stop_services() {
    check_compose
    
    echo "停止E2B服务..."
    docker-compose -f "$COMPOSE_FILE" down
    
    echo -e "${GREEN}服务已停止${NC}"
}

restart_services() {
    stop_services
    sleep 2
    start_services
}

show_status() {
    check_compose
    
    echo "E2B服务状态:"
    echo ""
    docker-compose -f "$COMPOSE_FILE" ps
    
    echo ""
    echo "资源使用:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" | head -10
}

show_logs() {
    check_compose
    
    local service="$1"
    
    if [ -z "$service" ]; then
        echo "显示所有服务日志 (Ctrl+C退出)..."
        docker-compose -f "$COMPOSE_FILE" logs -f
    else
        echo "显示 $service 服务日志 (Ctrl+C退出)..."
        docker-compose -f "$COMPOSE_FILE" logs -f "$service"
    fi
}

backup_data() {
    check_compose
    
    local backup_dir="$E2B_DIR/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    echo "备份E2B数据到: $backup_dir"
    
    # 备份数据库
    echo "备份数据库..."
    docker-compose -f "$COMPOSE_FILE" exec -T postgres pg_dump -U "${POSTGRES_USER:-postgres}" "${POSTGRES_DB:-e2b}" > "$backup_dir/database.sql"
    
    # 备份配置
    echo "备份配置文件..."
    cp "$COMPOSE_FILE" "$backup_dir/"
    cp "$CONFIG_DIR/.env.e2b" "$backup_dir/" 2>/dev/null || true
    
    # 备份重要数据
    echo "备份数据卷..."
    docker run --rm -v e2b_postgres_data:/source -v "$backup_dir":/backup alpine tar -czf /backup/postgres_data.tar.gz -C /source .
    
    echo -e "${GREEN}备份完成${NC}"
    echo "备份位置: $backup_dir"
    ls -lh "$backup_dir"
}

restore_backup() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        echo -e "${RED}错误: 请指定备份文件${NC}"
        echo "用法: $0 restore <备份目录>"
        exit 1
    fi
    
    if [ ! -d "$backup_file" ]; then
        echo -e "${RED}错误: 备份目录不存在${NC}"
        exit 1
    fi
    
    echo "警告: 恢复备份将覆盖当前数据!"
    read -p "确认恢复备份? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "取消恢复"
        exit 0
    fi
    
    # 停止服务
    stop_services
    
    # 恢复数据卷
    echo "恢复数据卷..."
    docker run --rm -v e2b_postgres_data:/target -v "$backup_file":/backup alpine tar -xzf /backup/postgres_data.tar.gz -C /target
    
    # 启动服务
    start_services
    
    # 恢复数据库
    echo "恢复数据库..."
    sleep 10  # 等待数据库启动
    docker-compose -f "$COMPOSE_FILE" exec -T postgres psql -U "${POSTGRES_USER:-postgres}" "${POSTGRES_DB:-e2b}" < "$backup_file/database.sql"
    
    echo -e "${GREEN}恢复完成${NC}"
}

cleanup() {
    echo "清理E2B缓存和临时文件..."
    
    # 清理Docker资源
    docker system prune -f
    
    # 清理临时文件
    rm -rf /tmp/e2b-*
    rm -rf "$E2B_DIR/tmp/*"
    
    # 清理日志文件 (保留最近7天)
    find "$E2B_DIR/logs" -name "*.log" -mtime +7 -delete 2>/dev/null || true
    
    echo -e "${GREEN}清理完成${NC}"
}

health_check() {
    echo "E2B健康检查..."
    echo ""
    
    # 检查服务状态
    show_status
    
    echo ""
    echo "API健康检查:"
    if curl -s "http://localhost:${E2B_API_PORT:-3000}/health" | grep -q "healthy"; then
        echo -e "${GREEN}✓ API健康${NC}"
    else
        echo -e "${RED}✗ API异常${NC}"
    fi
    
    echo ""
    echo "数据库连接:"
    if docker-compose -f "$COMPOSE_FILE" exec -T postgres pg_isready -U "${POSTGRES_USER:-postgres}"; then
        echo -e "${GREEN}✓ 数据库连接正常${NC}"
    else
        echo -e "${RED}✗ 数据库连接失败${NC}"
    fi
    
    echo ""
    echo "Redis连接:"
    if docker-compose -f "$COMPOSE_FILE" exec -T redis redis-cli ping | grep -q "PONG"; then
        echo -e "${GREEN}✓ Redis连接正常${NC}"
    else
        echo -e "${RED}✗ Redis连接失败${NC}"
    fi
}

init_config() {
    echo "初始化E2B配置..."
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    
    # 创建环境变量文件
    if [ ! -f "$CONFIG_DIR/.env.e2b" ]; then
        echo "创建环境变量配置文件..."
        cp "$CONFIG_DIR/.env.e2b.example" "$CONFIG_DIR/.env.e2b"
        echo -e "${YELLOW}请编辑 $CONFIG_DIR/.env.e2b 文件修改配置${NC}"
    fi
    
    # 创建数据目录
    mkdir -p "$E2B_DIR/data"
    mkdir -p "$E2B_DIR/logs"
    mkdir -p "$E2B_DIR/backups"
    mkdir -p "$E2B_DIR/tmp"
    
    # 设置权限
    chmod 755 "$E2B_DIR/data" "$E2B_DIR/logs" "$E2B_DIR/backups" "$E2B_DIR/tmp"
    
    echo -e "${GREEN}配置初始化完成${NC}"
}

update_images() {
    echo "更新E2B镜像..."
    
    check_docker
    check_compose
    
    # 拉取最新镜像
    docker-compose -f "$COMPOSE_FILE" pull
    
    # 重启服务
    restart_services
    
    echo -e "${GREEN}镜像更新完成${NC}"
}

# 主函数
main() {
    local command="$1"
    
    case "$command" in
        start)
            start_services
            ;;
        stop)
            stop_services
            ;;
        restart)
            restart_services
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs "$2"
            ;;
        backup)
            backup_data
            ;;
        restore)
            restore_backup "$2"
            ;;
        cleanup)
            cleanup
            ;;
        health)
            health_check
            ;;
        init)
            init_config
            ;;
        update)
            update_images
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            if [ -z "$command" ]; then
                show_help
            else
                echo -e "${RED}未知命令: $command${NC}"
                show_help
                exit 1
            fi
            ;;
    esac
}

# 运行主函数
main "$@"