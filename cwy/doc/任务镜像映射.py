#!/usr/bin/env python3
"""
86个任务的镜像需求映射表（Python版本）
用于编程查询和自动化脚本

使用示例：
    from 任务镜像映射 import TaskImageMapper
    
    mapper = TaskImageMapper()
    images = mapper.get_images_for_task("k8s_target_port-misconfig-detection-1")
    print(f"需要的镜像数量: {len(images)}")
"""

class TaskImageMapper:
    """任务到镜像的映射工具类"""
    
    def __init__(self):
        # 基础设施镜像（所有任务都需要）
        self.BASE_IMAGES = [
            # OpenEBS (5个)
            "openebs/provisioner-localpv:3.4.0",
            "openebs/linux-utils:3.5.0",
            "openebs/node-disk-exporter:2.1.0",
            "openebs/node-disk-operator:2.1.0",
            "openebs/node-disk-manager:2.1.0",
            
            # Prometheus (7个)
            "quay.io/prometheus/blackbox-exporter:v0.24.0",
            "quay.io/prometheus/node-exporter:v1.6.1",
            "quay.io/prometheus-operator/prometheus-config-reloader:v0.67.0",
            "quay.io/prometheus/prometheus:v2.47.2",
            "quay.io/prometheus/pushgateway:v1.6.2",
            "registry.cn-wulanchabu.aliyuncs.com/moge1/kube-state-metrics:v2.3.0",
            "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.1",
            
            # Chaos Mesh (4个)
            "ghcr.io/chaos-mesh/chaos-mesh:v2.6.2",
            "ghcr.io/chaos-mesh/chaos-daemon:v2.6.2",
            "ghcr.io/chaos-mesh/chaos-dashboard:v2.6.2",
            "ghcr.io/chaos-mesh/chaos-coredns:v0.2.6",
        ]
        
        # Social Network 应用镜像
        self.SOCIAL_NETWORK_IMAGES = [
            "deathstarbench/social-network-microservices:latest",
            "jaegertracing/all-in-one:1.57",
            "memcached:1.6.7",
            "redis:6.2.4",
            "mongo:4.4.6",
            "yg397/openresty-thrift:xenial",
            "yg397/media-frontend:xenial",
            "alpine/git:latest",
            "deathstarbench/wrk2-client:latest",
        ]
        
        # Hotel Reservation 应用镜像
        self.HOTEL_RESERVATION_IMAGES = [
            "deathstarbench/hotel-reservation:latest",
            "hashicorp/consul:latest",
            "igorrudyk1/hotel_reserv_frontend_single_node:latest",
            "igorrudyk1/hotel_reserv_geo_single_node:latest",
            "igorrudyk1/hotel_reserv_profile_single_node:latest",
            "igorrudyk1/hotel_reserv_rate_single_node:latest",
            "igorrudyk1/hotel_reserv_recommendation_single_node:latest",
            "igorrudyk1/hotel_reserv_reserve_single_node:latest",
            "igorrudyk1/hotel_reserv_search_single_node:latest",
            "igorrudyk1/hotel_reserv_user_single_node:latest",
            "yinfangchen/hotelreservation:latest",
            "memcached:latest",
            "memcached:1.6.7",
            "mongo:4.4.6",
            "deathstarbench/wrk2-client:latest",
        ]
        
        # Astronomy Shop 应用镜像
        self.ASTRONOMY_SHOP_IMAGES = [
            "ghcr.io/open-telemetry/demo:1.11.2",
            "otel/opentelemetry-collector-contrib:0.118.0",
            "busybox:latest",
            "redis:7.0-alpine",
            "bitnami/kafka:latest",
            "postgres:16",
        ]
        
        # 任务名前缀 -> 应用类型映射
        self.TASK_PREFIX_TO_APP = {
            # Social Network
            "k8s_target_port-misconfig": "social_network",
            "auth_miss_mongodb": "social_network",
            "scale_pod_zero_social_net": "social_network",
            "assign_to_non_existent_node_social_net": "social_network",
            
            # Hotel Reservation
            "revoke_auth_mongodb": "hotel_reservation",
            "user_unregistered_mongodb": "hotel_reservation",
            "misconfig_app_hotel_res": "hotel_reservation",
            "container_kill": "hotel_reservation",
            "pod_failure_hotel_res": "hotel_reservation",
            "pod_kill_hotel_res": "hotel_reservation",
            "network_loss_hotel_res": "hotel_reservation",
            "network_delay_hotel_res": "hotel_reservation",
            "redeploy_without_PV": "hotel_reservation",
            "wrong_bin_usage": "hotel_reservation",
            
            # Astronomy Shop
            "astronomy_shop_ad_service_failure": "astronomy_shop",
            "astronomy_shop_ad_service_high_cpu": "astronomy_shop",
            "astronomy_shop_ad_service_manual_gc": "astronomy_shop",
            "astronomy_shop_cart_service_failure": "astronomy_shop",
            "astronomy_shop_image_slow_load": "astronomy_shop",
            "astronomy_shop_kafka_queue_problems": "astronomy_shop",
            "astronomy_shop_loadgenerator_flood_homepage": "astronomy_shop",
            "astronomy_shop_payment_service_failure": "astronomy_shop",
            "astronomy_shop_payment_service_unreachable": "astronomy_shop",
            "astronomy_shop_product_catalog_service_failure": "astronomy_shop",
            "astronomy_shop_recommendation_service_cache_failure": "astronomy_shop",
        }
    
    def get_application_type(self, task_name: str) -> str:
        """
        根据任务名获取应用类型
        
        Args:
            task_name: 任务名称，例如 "k8s_target_port-misconfig-detection-1"
        
        Returns:
            应用类型: "social_network", "hotel_reservation", "astronomy_shop", 或 "unknown"
        """
        # 处理 noop 任务
        if "noop_detection" in task_name:
            if "hotel_reservation" in task_name:
                return "hotel_reservation"
            elif "social_network" in task_name:
                return "social_network"
            elif "astronomy_shop" in task_name:
                return "astronomy_shop"
        
        # 根据前缀匹配
        for prefix, app_type in self.TASK_PREFIX_TO_APP.items():
            if task_name.startswith(prefix):
                return app_type
        
        return "unknown"
    
    def get_application_images(self, app_type: str) -> list:
        """
        获取特定应用类型的镜像列表
        
        Args:
            app_type: 应用类型
        
        Returns:
            该应用的镜像列表
        """
        if app_type == "social_network":
            return self.SOCIAL_NETWORK_IMAGES.copy()
        elif app_type == "hotel_reservation":
            return self.HOTEL_RESERVATION_IMAGES.copy()
        elif app_type == "astronomy_shop":
            return self.ASTRONOMY_SHOP_IMAGES.copy()
        else:
            return []
    
    def get_images_for_task(self, task_name: str) -> list:
        """
        获取特定任务需要的所有镜像
        
        Args:
            task_name: 任务名称
        
        Returns:
            该任务需要的所有镜像列表（基础设施 + 应用镜像）
        """
        app_type = self.get_application_type(task_name)
        app_images = self.get_application_images(app_type)
        
        # 去重合并
        all_images = list(set(self.BASE_IMAGES + app_images))
        all_images.sort()
        
        return all_images
    
    def get_image_count_for_task(self, task_name: str) -> int:
        """获取任务需要的镜像数量"""
        return len(self.get_images_for_task(task_name))
    
    def get_all_unique_images(self) -> list:
        """获取所有唯一镜像（用于全镜像方案）"""
        all_images = set()
        all_images.update(self.BASE_IMAGES)
        all_images.update(self.SOCIAL_NETWORK_IMAGES)
        all_images.update(self.HOTEL_RESERVATION_IMAGES)
        all_images.update(self.ASTRONOMY_SHOP_IMAGES)
        
        return sorted(list(all_images))
    
    def recommend_kind_for_task(self, task_name: str) -> str:
        """
        推荐使用哪个Kind范围来运行任务（优化方案）
        
        Args:
            task_name: 任务名称
        
        Returns:
            推荐的Kind范围，例如 "kind1-30"
        """
        app_type = self.get_application_type(task_name)
        
        if app_type == "social_network":
            return "kind1-30"
        elif app_type == "hotel_reservation":
            return "kind31-65"
        elif app_type == "astronomy_shop":
            return "kind66-86"
        else:
            return "unknown"
    
    def print_task_info(self, task_name: str):
        """打印任务的详细信息"""
        app_type = self.get_application_type(task_name)
        images = self.get_images_for_task(task_name)
        recommended_kind = self.recommend_kind_for_task(task_name)
        
        print(f"任务: {task_name}")
        print(f"应用类型: {app_type}")
        print(f"需要镜像数量: {len(images)}")
        print(f"推荐Kind范围: {recommended_kind}")
        print(f"\n镜像列表:")
        for i, img in enumerate(images, 1):
            print(f"  {i}. {img}")


# 使用示例
if __name__ == "__main__":
    mapper = TaskImageMapper()
    
    # 测试几个任务
    test_tasks = [
        "k8s_target_port-misconfig-detection-1",
        "revoke_auth_mongodb-detection-1",
        "astronomy_shop_ad_service_failure-detection-1",
    ]
    
    print("=" * 80)
    print("任务镜像映射工具 - 使用示例")
    print("=" * 80)
    print()
    
    for task in test_tasks:
        mapper.print_task_info(task)
        print("\n" + "-" * 80 + "\n")
    
    # 统计信息
    print("=" * 80)
    print("统计信息")
    print("=" * 80)
    print(f"基础设施镜像数量: {len(mapper.BASE_IMAGES)}")
    print(f"Social Network 镜像数量: {len(mapper.SOCIAL_NETWORK_IMAGES)}")
    print(f"Hotel Reservation 镜像数量: {len(mapper.HOTEL_RESERVATION_IMAGES)}")
    print(f"Astronomy Shop 镜像数量: {len(mapper.ASTRONOMY_SHOP_IMAGES)}")
    print(f"所有唯一镜像数量: {len(mapper.get_all_unique_images())}")

