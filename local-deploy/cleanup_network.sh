#!/bin/bash
# 清理孤立的网络命名空间

echo "清理孤立的网络命名空间..."

for ns in $(ip netns list | awk '{print $1}'); do
    echo "删除网络命名空间: $ns"
    sudo ip netns delete "$ns" 2>&1
done

echo "清理完成！"
echo "剩余网络命名空间数量: $(ip netns list | wc -l)"
