#!/bin/bash

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🛑 停止所有测评任务"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 停止 gpt.py 相关进程
echo "1️⃣  停止 gpt.py 进程..."
pkill -f "clients/gpt.py"
sleep 2

# 检查是否还有残留进程
REMAINING=$(ps aux | grep "clients/gpt.py" | grep -v grep | wc -l)

if [ $REMAINING -eq 0 ]; then
    echo "   ✅ 所有 gpt.py 进程已停止"
else
    echo "   ⚠️  还有 $REMAINING 个进程未停止，强制结束..."
    pkill -9 -f "clients/gpt.py"
    sleep 1
    echo "   ✅ 强制停止完成"
fi

echo ""
echo "2️⃣  显示最后的日志（如果有）..."
if [ -f logs/gpt_eval.log ]; then
    echo ""
    echo "━━━ 最后 10 行日志 ━━━"
    tail -10 logs/gpt_eval.log
    echo ""
else
    echo "   ℹ️  没有找到日志文件"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 停止完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
