## 11.20
# 实验
测试一个kind 11指令
cd /home/ecs-user/projects/AI_SRE_Playground-echo
nohup bash run_kind11_test.sh > logs/test/kind11_wrapper.log 2>&1 &



# 分析
对了 把kind21-86 删除 然后重启机器是不是可以试试？ 你先分析这个方案
1.删除21-86 kind 
2.看目前机器怎么样

别的机器利用率竟然是i00
(base) wanyi@ip-172-21-11-37:~/projects$ for container in $(docker ps --filter "name=kind.*-control-plane" --format "{{.Names}}"); do
  echo "=== $container ==="
  docker exec $container cat /proc/slabinfo 2>/dev/null | grep tw_sock_TCP | awk '{printf "%s: %d / %d (%.1f%%)\n", $1, $2, $3, $2*100/$3}'
  echo ""
done
=== kind-control-plane ===
tw_sock_TCPv6: 1240 / 1240 (100.0%)
tw_sock_TCP: 3131 / 3131 (100.0%)

=== kind-cluster-control-plane ===
tw_sock_TCPv6: 1240 / 1240 (100.0%)
tw_sock_TCP: 3131 / 3131 (100.0%)

=== kind-yp-control-plane ===
tw_sock_TCPv6: 1240 / 1240 (100.0%)
tw_sock_TCP: 3131 / 3131 (100.0%)

(base) wanyi@ip-172-21-11-37:~/projects$ 

重启机器：sudo reboot

docker ps --filter "name=kind.*-control-plane" --format "{{.Names}}"
kind-control-plane
kind-cluster-control-plane

