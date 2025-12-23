#!/bin/bash
# 配置Docker使用国内镜像源

set -e

echo "======================================================"
echo "  配置Docker使用国内镜像源"
echo "======================================================"
echo ""

# 备份原有配置
if [ -f /etc/docker/daemon.json ]; then
  echo "备份原有Docker配置..."
  sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup.$(date +%Y%m%d%H%M%S)
fi

echo ""
echo "配置Docker镜像加速..."
echo ""

# 创建新的daemon.json配置
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://dockerproxy.com",
    "https://docker.mirrors.ustc.edu.cn",
    "https://docker.nju.edu.cn"
  ],
  "max-concurrent-downloads": 10,
  "max-download-attempts": 50,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF

echo "✓ Docker配置已更新"
echo ""
echo "新配置内容:"
cat /etc/docker/daemon.json
echo ""

echo "重启Docker服务..."
sudo systemctl daemon-reload
sudo systemctl restart docker

echo ""
echo "等待Docker启动..."
sleep 5

echo ""
echo "验证Docker状态..."
sudo systemctl status docker --no-pager | head -15

echo ""
echo "测试Docker拉取..."
docker pull alpine:3.18 || {
  echo "⚠ Docker拉取测试失败，但配置已更新"
  echo "  可能需要等待网络恢复或检查代理设置"
}

echo ""
echo "======================================================"
echo "  Docker镜像加速配置完成！"
echo "======================================================"
echo ""
echo "现在可以运行构建脚本:"
echo "  /home/primihub/pcloud/infra/rebuild-and-deploy.sh"
echo ""
