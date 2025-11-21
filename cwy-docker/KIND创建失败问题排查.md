# Kind 集群创建失败问题排查记录

**日期**: 2025-11-18  
**问题**: Docker 迁移到 `/data` 分区后，无法创建新的 Kind 集群（kind11 及以后）

---

## 📊 背景信息

### 系统环境
- **OS**: Linux 6.8.0-57-generic
- **Docker**: 28.2.2
- **Kind**: v0.27.0
- **现有集群**: kind, kind1-kind10（共11个集群，创建于 2025-10-31）
- **新集群创建**: 2025-11-18 无法创建

### Docker 迁移情况
- **迁移时间**: 2025-11-18 18:15-18:56（约40分钟）
- **迁移方式**: rsync 复制 + 软链接
- **原路径**: `/var/lib/docker`（根分区）
- **新路径**: `/data/docker`（2TB 独立分区）
- **迁移结果**: ✅ 成功，所有现有容器正常运行

---

## ❌ 问题现象

### 错误信息
```bash
kind create cluster --name kind11 --image kindest/node:v1.27.3

# 报错：
ERROR: failed to create cluster: could not find a log line that matches 
"Reached target .*Multi-User System.*|detected cgroup v1"
```

### 容器日志
```
INFO: starting init
systemd 252.33-1~deb12u1 running in system mode...
Welcome to Debian GNU/Linux 12 (bookworm)!

Failed to create control group inotify object: Too many open files
Failed to allocate manager object: Too many open files
[!!!!!] Failed to allocate manager object.
Exiting PID 1...
```

**容器 Exit Code**: 255（systemd 无法启动）

---

## 🔍 排查过程

### 1. 迁移相关排查
- ❌ **Docker 迁移导致？** → 切换回原始备份，**仍然失败**
- ✅ **文件系统差异？** → 两个分区都是 ext4，挂载选项相同
- ✅ **软链接问题？** → 软链接正常工作

**结论**: **不是迁移导致的问题**

---

### 2. 网络相关排查
- ❌ **需要外网？** → 断网测试，**仍然失败**
- ✅ **镜像缺失？** → 所有镜像都在本地（kindest/node:v1.27.3）

**结论**: **不是网络问题**

---

### 3. 系统资源排查

| 资源类型 | 限制 | 当前使用 | 状态 |
|---------|------|---------|------|
| **CPU** | 96 核 | 负载 < 1.0 | ✅ 正常 |
| **内存** | 372 GB | 使用 10 GB | ✅ 正常 |
| **磁盘** | 2 TB (/data) | 使用 297 GB | ✅ 正常 |
| **文件句柄** | 1048576 | 64702 | ✅ 正常 |
| **inotify instances** | 128 → **512** ⚠️ | 2 | ⚠️ 已调整 |
| **inotify watches** | 1048576 → **524288** | - | ✅ 充足 |

**结论**: **资源充足，但 inotify 限制可能有问题**

---

### 4. 系统配置排查

#### inotify 限制调整
```bash
# 已执行的优化
sudo sysctl fs.inotify.max_user_instances=512
sudo sysctl -w fs.inotify.max_user_watches=524288

# 永久保存
echo "fs.inotify.max_user_instances = 512" >> /etc/sysctl.conf
echo "fs.inotify.max_user_watches = 524288" >> /etc/sysctl.conf
```

**结果**: **调整后仍然失败**

#### Docker 重启测试
```bash
sudo systemctl restart docker
```

**结果**: **重启后仍然失败**

---

## 🎯 根本原因分析

### 关键发现
1. **现有集群正常运行**（kind-kind10，创建于 10月31日）
2. **新集群无法创建**（kind11 及以后，11月18日开始）
3. **systemd 启动失败**：`Too many open files`
4. **问题与 Docker 迁移无关**

### 可能原因
1. **系统更新**：10月31日 → 11月18日之间可能有系统更新
2. **内核参数变化**：某些内核参数可能被重置或修改
3. **systemd 版本变化**：可能有 systemd 升级
4. **Docker 版本变化**：可能有 Docker 升级
5. **容器镜像问题**：jacksonarthurclark/aiopslab-kind-x86:latest 可能有兼容性问题

---

## 💡 后续解决方案

### 方案 1：深入排查系统配置（推荐）
```bash
# 1. 检查系统更新历史
grep " install \| upgrade " /var/log/dpkg.log* | grep -E "docker|systemd|kernel"

# 2. 检查内核参数变化
sudo sysctl -a | grep -E "fs\.|kernel\." > /tmp/sysctl_current.txt

# 3. 对比 Docker 版本
docker version --format '{{.Server.Version}}'

# 4. 检查 systemd 版本
systemctl --version
```

**询问老师**：
- 是否在 10月31日 - 11月18日之间做过系统升级？
- 是否修改过内核参数或 Docker 配置？
- 是否重启过服务器？

---

### 方案 2：调整更多系统限制
```bash
# 增加进程限制
sudo sysctl -w kernel.pid_max=4194304

# 增加文件系统限制
sudo sysctl -w fs.file-max=2097152

# 增加用户进程限制
echo "* soft nofile 1048576" >> /etc/security/limits.conf
echo "* hard nofile 1048576" >> /etc/security/limits.conf

# 重启生效
sudo reboot
```

---

### 方案 3：使用不同的 Kind 镜像
```bash
# 尝试使用官方镜像
kind create cluster --name kind11 --image kindest/node:v1.27.3

# 尝试使用带镜像的版本
kind create cluster --name kind11 --image kindest/node:v1.27.3-with-images

# 尝试降级镜像版本
kind create cluster --name kind11 --image kindest/node:v1.26.0
```

---

### 方案 4：临时方案（使用现有集群）
**优点**：
- 现有 11 个集群完全正常
- 可以立即开始测试并行任务
- 不影响项目进度

**限制**：
- 最多同时运行 11 个并行任务
- 无法扩展到 86 个集群

---

### 方案 5：手动创建容器（绕过 Kind）
```bash
# 参考 kind10 的配置手动创建
docker inspect kind10-control-plane --format '{{json .HostConfig}}' > kind10_config.json

# 使用相同配置创建新容器
docker run -d --privileged \
  --name kind11-control-plane \
  -v /lib/modules:/lib/modules:ro \
  -v /run/udev:/run/udev \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  kindest/node:v1.27.3
```

---

## 📋 测试清单

### 立即测试（5分钟）
- [ ] 检查系统更新历史
- [ ] 对比现有集群的创建参数
- [ ] 尝试不同的 Kind 镜像版本

### 中期测试（需要重启）
- [ ] 调整所有系统限制
- [ ] 重启服务器
- [ ] 重新测试创建

### 长期方案
- [ ] 咨询 Kind 社区
- [ ] 升级 Kind 版本
- [ ] 考虑替代容器编排方案

---

## 📞 联系信息

**问题联系**：
- 如果老师确认有系统更新，检查更新日志
- 如果需要紧急使用，建议先用方案4（现有11个集群）
- 如果要继续排查，建议按方案1的顺序执行

**相关文件**：
- 迁移脚本：`/home/ecs-user/projects/AI_SRE_Playground-echo/cwy-docker/migrate_docker_to_data.sh`
- 批量创建脚本：`/home/ecs-user/projects/AI_SRE_Playground-echo/cwy-docker/create_kinds_11_to_86.sh`
- 日志目录：`/home/ecs-user/projects/AI_SRE_Playground-echo/logs/docker/`

