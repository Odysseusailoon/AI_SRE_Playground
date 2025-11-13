# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

"""Abstracts the configuration file for AIOpsLab."""

import yaml


class Config:
    def __init__(self, config_path):
        self.config_path = config_path
        self.config = self._load_config()

    def _load_config(self):
        with open(self.config_path, "r") as file:
            return yaml.safe_load(file)

    def get(self, key, default=None):
        return self.config.get(key, default)


def get_kube_context():
    """Get the kubernetes context from config.yml with consistent priority logic
    
    Priority (highest to lowest):
    1. Environment variable AIOPSLAB_CLUSTER (for parallel execution)
    2. Explicit kube_context setting
    3. If k8s_host is 'kind', construct from kind_cluster_name
    4. No context (return None to use system default)
    
    Returns:
        str or None: Context name if should be specified, None if should use default
    """
    import os
    
    # Priority 1: Environment variable (for parallel execution)
    cluster_env = os.environ.get('AIOPSLAB_CLUSTER')
    if cluster_env:
        return f"kind-{cluster_env}"
    
    try:
        # Import BASE_DIR inside function to avoid circular import
        from aiopslab.paths import BASE_DIR
        config_yaml = Config(BASE_DIR / "config.yml")
        
        # Priority 2: Explicit kube_context setting
        kube_context = config_yaml.get("kube_context")
        if kube_context:
            return kube_context
        
        # Priority 3: If k8s_host is kind, construct from kind_cluster_name
        k8s_host = config_yaml.get("k8s_host")
        if k8s_host == "kind":
            cluster_name = config_yaml.get("kind_cluster_name", "kind")
            return f"kind-{cluster_name}"
        
        # Priority 4: No context specified, use system default
        return None
        
    except Exception:
        # If config reading fails, use system default
        return None


# Usage example
# config = Config(Path("config.yml"))
# data_dir = config.get("data_dir")
# qualitative_eval = config.get("qualitative_eval")
