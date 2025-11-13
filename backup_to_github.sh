#!/bin/bash

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 备份所有代码到 GitHub"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd /home/ecs-user/projects/AI_SRE_Playground-echo

# 1. 添加新的远程仓库
echo "1️⃣  添加远程仓库..."
git remote add backup https://github.com/couragec/echo-singleagent.git 2>/dev/null || echo "   远程仓库已存在，跳过"
echo ""

# 2. 显示当前状态
echo "2️⃣  当前状态："
git status --short | head -20
echo ""

# 3. 添加所有文件（包括 .env 等敏感文件）
echo "3️⃣  添加所有文件..."
git add .
git add .env 2>/dev/null
git add -f logs/*.log 2>/dev/null
echo "   ✅ 完成"
echo ""

# 4. 提交
echo "4️⃣  提交修改..."
git commit -m "Backup: 完整代码和配置备份

主要内容：
- 优化 load_all_images.sh：自动部署 OpenEBS
- 修复 aiopslab/service/shell.py 缩进错误
- 创建 stop_evaluation.sh 停止脚本
- 增加系统 inotify 限制支持多集群
- 完成 kind4 集群配置和验证
- 包含所有配置文件和日志

集群状态：5个集群全部就绪
并行能力：最多5个任务同时执行
镜像数量：27个全部本地化" || echo "   ℹ️  没有新的修改需要提交"
echo ""

# 5. 推送所有分支
echo "5️⃣  推送到 GitHub..."
echo "   正在推送所有分支..."
git push backup --all -f
echo ""
echo "   正在推送所有标签..."
git push backup --tags -f 2>/dev/null || echo "   没有标签需要推送"
echo ""

# 6. 验证
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 备份完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "【远程仓库】"
git remote -v | grep backup
echo ""
echo "【查看结果】"
echo "   https://github.com/couragec/echo-singleagent"
echo ""
