#!/bin/bash

# 为 86 个 Kind 集群调整 inotify 限制
# 每个 Kind 集群大约需要 50-100 个 inotify instances

echo "=== 当前 inotify 配置 ==="
sysctl fs.inotify.max_user_instances
sysctl fs.inotify.max_user_watches

echo ""
echo "=== 当前使用情况 ==="
CURRENT_USAGE=$(sudo find /proc/*/fd -lname "anon_inode:inotify" 2>/dev/null | wc -l)
echo "当前使用: $CURRENT_USAGE 个 inotify instances"

echo ""
echo "=== 设置新限制（支持 86 个 Kind） ==="
# 86 个 Kind × 100 instances/Kind = 8600，留出余量设为 10000
sudo sysctl -w fs.inotify.max_user_instances=10000
sudo sysctl -w fs.inotify.max_user_watches=1048576

# 持久化配置
sudo tee /etc/sysctl.d/99-kind-inotify.conf > /dev/null << SYSCTL
fs.inotify.max_user_instances = 10000
fs.inotify.max_user_watches = 1048576
SYSCTL

echo ""
echo "=== 验证新配置 ==="
sysctl fs.inotify.max_user_instances
sysctl fs.inotify.max_user_watches

echo ""
echo "✅ inotify 限制已提升，现在可以创建 Kind 集群了"
