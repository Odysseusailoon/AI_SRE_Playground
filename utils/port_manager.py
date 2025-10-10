"""
端口管理工具 - 解决端口冲突问题
"""
import subprocess
import time
import socket
from contextlib import closing
from typing import Optional, Set, Dict
import os
import signal


class PortManager:
    """统一管理所有端口转发"""

    # 使用的端口记录
    _used_ports: Set[int] = set()
    _port_processes: Dict[int, any] = {}  # port -> process

    @classmethod
    def cleanup_all_port_forwards(cls):
        """清理所有kubectl port-forward进程"""
        try:
            # 方法1：使用pkill
            result = subprocess.run(
                ["pkill", "-f", "kubectl.*port-forward"],
                capture_output=True,
                text=True,
                timeout=5
            )

            if result.returncode == 0:
                print("✅ Cleaned up all port-forward processes")

            # 方法2：通过端口号清理特定范围
            for port in range(32000, 32100):
                cls.kill_port_process(port)

            cls._used_ports.clear()
            cls._port_processes.clear()

            # 等待端口释放
            time.sleep(1)

        except subprocess.TimeoutExpired:
            print("⚠️ Timeout during cleanup, forcing kill...")
            subprocess.run(["pkill", "-9", "-f", "kubectl.*port-forward"], capture_output=True)

        except Exception as e:
            print(f"⚠️ Error during cleanup: {e}")

    @classmethod
    def kill_port_process(cls, port: int):
        """杀死占用指定端口的进程"""
        try:
            # Linux/Mac命令
            cmd = f"lsof -ti :{port}"
            result = subprocess.run(
                cmd,
                shell=True,
                capture_output=True,
                text=True
            )

            if result.stdout:
                pids = result.stdout.strip().split('\n')
                for pid in pids:
                    if pid and pid.isdigit():
                        try:
                            os.kill(int(pid), signal.SIGKILL)
                            print(f"✅ Killed process {pid} on port {port}")
                        except ProcessLookupError:
                            pass
        except Exception as e:
            # 静默处理，因为端口可能未被使用
            pass

    @classmethod
    def is_port_available(cls, port: int, host: str = 'localhost') -> bool:
        """检查端口是否可用"""
        with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as sock:
            try:
                sock.bind((host, port))
                return True
            except OSError:
                return False

    @classmethod
    def find_available_port(cls, start_port: int = 32000, end_port: int = 32100) -> Optional[int]:
        """查找可用端口"""
        for port in range(start_port, end_port):
            if port not in cls._used_ports and cls.is_port_available(port):
                cls._used_ports.add(port)
                return port
        return None

    @classmethod
    def release_port(cls, port: int):
        """释放端口"""
        if port in cls._used_ports:
            cls._used_ports.remove(port)

        cls.kill_port_process(port)

        if port in cls._port_processes:
            del cls._port_processes[port]

    @classmethod
    def cleanup_prometheus_ports(cls):
        """专门清理Prometheus相关的端口转发"""
        try:
            subprocess.run(
                ["pkill", "-f", "kubectl.*port-forward.*prometheus"],
                capture_output=True,
                text=True
            )
            print("✅ Cleaned up Prometheus port-forward processes")
        except Exception as e:
            print(f"⚠️ Error cleaning Prometheus ports: {e}")

    @classmethod
    def ensure_port_available(cls, port: int, max_retries: int = 3) -> bool:
        """确保指定端口可用"""
        for retry in range(max_retries):
            if cls.is_port_available(port):
                return True

            print(f"🔄 Port {port} is busy, cleaning up... (attempt {retry + 1}/{max_retries})")
            cls.kill_port_process(port)
            time.sleep(1)

        return False