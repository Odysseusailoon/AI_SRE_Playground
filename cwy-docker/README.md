# Docker 迁移和 Kind 集群批量创建工具

本目录包含 Docker 数据迁移和批量创建 Kind 集群的所有脚本。

## 📁 目录结构

```
cwy-docker/
├── migrate_docker_to_data.sh      # Docker 迁移核心脚本
├── start_migration.sh             # 后台启动迁移
├── monitor_migration.sh           # 监控迁移进度
├── create_kinds_11_to_86.sh       # 批量创建 Kind 集群 (kind11-kind86)
└── README.md                      # 本文档
```

## 📋 使用流程

### 阶段1：迁移 Docker 到 /data（2TB 磁盘）

#### 1. 启动迁移（后台运行）
```bash
cd /home/ecs-user/projects/AI_SRE_Playground-echo/cwy-docker
./start_migration.sh
```

#### 2. 监控迁移进度
```bash
# 方式1：使用监控脚本
./monitor_migration.sh

# 方式2：实时查看日志
tail -f ../logs/docker/migration_console.log

# 方式3：查看详细日志
tail -f ../logs/docker/docker_migration_*.log
```

#### 3. 验证迁移成功
```bash
# 检查 Docker Root Dir
sudo docker info | grep "Docker Root Dir"
# 应该显示: /data/docker

# 检查软链接
ls -la /var/lib/docker
# 应该显示: /var/lib/docker -> /data/docker

# 验证现有 Kind 集群
kind get clusters
kubectl get nodes --all-namespaces
```

---

### 阶段2：批量创建 Kind 集群（kind11-kind86）

#### 1. 前台运行（推荐测试）
```bash
cd /home/ecs-user/projects/AI_SRE_Playground-echo/cwy-docker
./create_kinds_11_to_86.sh
```

#### 2. 后台运行（推荐正式）
```bash
cd /home/ecs-user/projects/AI_SRE_Playground-echo/cwy-docker
nohup ./create_kinds_11_to_86.sh > ../logs/docker/kind_batch_creation.log 2>&1 &
echo $!
```

#### 3. 监控创建进度
```bash
# 查看主日志
tail -f ../logs/docker/kind_creation/batch_creation_*.log

# 查看已创建集群数量
kind get clusters | wc -l

# 查看最新集群日志
ls -lt ../logs/docker/kind_creation/ | head -10
```

---

## 📊 预计时间和资源消耗

### Docker 迁移
- **时间**: 10-20 分钟（取决于现有 Docker 数据量）
- **操作**: 停止 Docker → 迁移数据 → 创建软链接 → 启动 Docker

### Kind 集群创建
- **数量**: 76 个集群（kind11 - kind86）
- **单个集群**: 2-4 分钟
- **总时间**: 约 2.5-5 小时
- **资源消耗**:
  - CPU: ~38 核
  - 内存: ~115 GB
  - 磁盘: ~150 GB

---

## 📋 日志文件位置

所有日志统一存放在：`/home/ecs-user/projects/AI_SRE_Playground-echo/logs/docker/`

### 迁移日志
```
logs/docker/
├── migration_console.log           # 迁移控制台输出
├── docker_migration_*.log          # 迁移详细日志
└── migration.pid                   # 迁移进程 ID
```

### Kind 创建日志
```
logs/docker/kind_creation/
├── batch_creation_*.log            # 批量创建主日志
├── kind11_*.log                    # kind11 详细日志
├── kind12_*.log                    # kind12 详细日志
└── ...
```

---

## 🔧 脚本功能详解

### migrate_docker_to_data.sh
**核心迁移脚本**
- ✅ 自动停止 Docker 服务
- ✅ 记录运行中的容器
- ✅ 使用 rsync 迁移数据（支持断点续传）
- ✅ 创建软链接 `/var/lib/docker` → `/data/docker`
- ✅ 自动启动 Docker 并恢复容器
- ✅ 验证 Kind 集群状态
- ✅ 详细日志记录

### start_migration.sh
**后台启动脚本**
- ✅ 预先验证 sudo 权限
- ✅ 后台运行迁移脚本
- ✅ 保存进程 ID
- ✅ 显示监控命令

### monitor_migration.sh
**监控脚本**
- ✅ 检查迁移进程状态
- ✅ 显示最新日志（最后 30 行）
- ✅ 提供实时监控提示

### create_kinds_11_to_86.sh
**批量创建 Kind 集群**
- ✅ 自动创建 kind11 - kind86（76 个集群）
- ✅ 加载所有必需镜像（应用 + OpenEBS + Prometheus）
- ✅ 安装基础设施（OpenEBS、Prometheus）
- ✅ 智能备份 socialNetwork 源代码（只复制一次）
- ✅ 容错处理（单个集群失败不影响其他集群）
- ✅ 详细日志记录（每个集群独立日志）
- ✅ 实时统计（进度、耗时、成功/失败数量）

---

## ⚠️ 注意事项

### Docker 迁移
1. ⚠️ 迁移期间 Docker 服务会停止，所有容器会暂停
2. ⚠️ 迁移完成后会自动恢复，但请确保没有关键服务正在运行
3. ✅ 现有集群会自动恢复，无需手动操作
4. ✅ 原目录会备份为 `/var/lib/docker.backup.*`
5. ✅ 确认一切正常后，可以删除备份释放空间

### Kind 集群创建
1. ✅ 脚本会顺序创建（非并行），确保稳定性
2. ✅ 单个集群失败不会中断整个流程
3. ✅ 最后会统一报告成功和失败的集群
4. ✅ socialNetwork 源代码会智能备份，加快创建速度
5. ⚠️ 如果需要修改集群范围，编辑 `create_kinds_11_to_86.sh` 的 `START_NUM` 和 `END_NUM`

---

## 🎯 快速开始

### 完整流程（一键执行）
```bash
# 1. 进入目录
cd /home/ecs-user/projects/AI_SRE_Playground-echo/cwy-docker

# 2. 迁移 Docker（后台）
./start_migration.sh

# 3. 等待迁移完成（监控）
./monitor_migration.sh

# 4. 迁移成功后，创建 Kind 集群（后台）
nohup ./create_kinds_11_to_86.sh > ../logs/docker/kind_batch_creation.log 2>&1 &

# 5. 监控创建进度
tail -f ../logs/docker/kind_creation/batch_creation_*.log
```

---

## 📞 故障排查

### 迁移失败
```bash
# 查看详细日志
cat ../logs/docker/docker_migration_*.log

# 手动启动 Docker
sudo systemctl start docker

# 检查 Docker 状态
sudo systemctl status docker
```

### Kind 创建失败
```bash
# 查看失败集群的详细日志
ls -lt ../logs/docker/kind_creation/*.log | head -5

# 删除失败的集群重新创建
kind delete cluster --name kindN
kind create cluster --name kindN
```

### 磁盘空间不足
```bash
# 检查磁盘使用
df -h

# 清理 Docker 未使用资源
sudo docker system prune -a

# 删除备份（确认迁移成功后）
sudo rm -rf /var/lib/docker.backup.*
```

---

## 📈 验证成功

### 迁移成功标志
- ✅ `sudo docker info | grep "Docker Root Dir"` 显示 `/data/docker`
- ✅ `ls -la /var/lib/docker` 显示软链接
- ✅ 所有现有 Kind 集群正常运行

### Kind 创建成功标志
- ✅ `kind get clusters` 显示 kind, kind1-kind10, kind11-kind86
- ✅ 总共 87 个集群
- ✅ 每个集群的节点状态为 Ready

---

**创建时间**: 2025-11-18  
**维护者**: cwy

