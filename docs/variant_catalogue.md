# Variant Catalogue

This catalogue summarizes the variant-enabled scenarios available to the reinforcement learning curriculum. For each problem family we list the variant knobs that are exercised, the fault injection entry points, and the evaluation signals agents must optimize.

## Hotel Reservation – Network Symptoms

### Network Loss Detection & Localization
- **Variant knobs:** Composite generator sweeps the faulty microservice label through the Hotel Reservation topology and varies packet loss severity via a numeric schedule.【F:aiopslab/orchestrator/problems/network_loss/network_loss_variant.py†L23-L55】
- **Fault model:** Every variant delegates to the `SymptomFaultInjector.inject_network_loss` helper, targeting the active service for loss injection.【F:aiopslab/orchestrator/problems/network_loss/network_loss_variant.py†L89-L99】
- **Evaluation:** Detection agents must answer "Yes" to achieve a `Detection Accuracy` reward, while localization agents are graded on `Localization Accuracy`, `success`, and subset flags derived from set comparisons against the injected service list.【F:aiopslab/orchestrator/problems/network_loss/network_loss_variant.py†L110-L168】

### Network Delay Detection & Localization
- **Variant knobs:** A composite generator rotates the impacted microservice and the injected latency (50–1000 ms) to stress agents across network tiers.【F:aiopslab/orchestrator/problems/network_delay/network_delay_variant.py†L23-L55】
- **Fault model:** Variants call `SymptomFaultInjector.inject_network_delay`, logging the currently selected service and delay budget.【F:aiopslab/orchestrator/problems/network_delay/network_delay_variant.py†L89-L100】
- **Evaluation:** As with network loss, detection expects a "Yes" submission and localization rewards exact or subset matches, emitting `Localization Accuracy`, `success`, and `is_subset` metrics.【F:aiopslab/orchestrator/problems/network_delay/network_delay_variant.py†L110-L168】

## Hotel Reservation – Pod Disruptions

### Pod Failure Detection & Localization
- **Variant knobs:** The service variant generator ranges across front-end, application, cache, and MongoDB services when selecting the failed pod.【F:aiopslab/orchestrator/problems/pod_failure/pod_failure_variant.py†L23-L48】
- **Fault model:** The `SymptomFaultInjector._inject` call issues a `pod_failure` chaos experiment scoped to the current service label.【F:aiopslab/orchestrator/problems/pod_failure/pod_failure_variant.py†L77-L89】
- **Evaluation:** Detection problems again check for "Yes", while localization computes accuracy from exact or subset matches and updates `success`/`is_subset` flags.【F:aiopslab/orchestrator/problems/pod_failure/pod_failure_variant.py†L100-L158】

### Pod Kill Detection & Localization
- **Variant knobs:** A composite generator couples service selection with discrete duration choices (50 s–300 s) to cover short-lived versus long-lived disruptions.【F:aiopslab/orchestrator/problems/pod_kill/pod_kill_variant.py†L23-L58】
- **Fault model:** `SymptomFaultInjector._inject` issues `pod_kill` with the active service list and the variant-specific duration.【F:aiopslab/orchestrator/problems/pod_kill/pod_kill_variant.py†L92-L104】
- **Evaluation:** Detection and localization follow the same scoring templates as above, logging `Detection Accuracy` or `Localization Accuracy` and boolean success summaries.【F:aiopslab/orchestrator/problems/pod_kill/pod_kill_variant.py†L115-L173】

### Container Kill Detection & Localization
- **Variant knobs:** A bespoke generator iterates through service/container name pairs so agents see container-level failures as well as service-level outages.【F:aiopslab/orchestrator/problems/container_kill/container_kill_variant.py†L24-L76】
- **Fault model:** Variants invoke `SymptomFaultInjector.inject_container_kill` with the synchronized service and container identifiers.【F:aiopslab/orchestrator/problems/container_kill/container_kill_variant.py†L112-L125】
- **Evaluation:** Detection requires the canonical "Yes" answer, and localization tracks accuracy plus `success` and `is_subset` results for the reported component list.【F:aiopslab/orchestrator/problems/container_kill/container_kill_variant.py†L134-L192】

## Hotel Reservation – Application Misconfiguration

### Misconfig Application Detection & Localization
- **Variant knobs:** Service variants span Hotel Reservation tiers while a configuration generator toggles environment, port, connection, memory, and timeout faults.【F:aiopslab/orchestrator/problems/misconfig_app/misconfig_app_variant.py†L24-L57】
- **Fault model:** The variant feeds the selected microservice to `ApplicationFaultInjector._inject` under the `misconfig_app` fault type.【F:aiopslab/orchestrator/problems/misconfig_app/misconfig_app_variant.py†L90-L99】
- **Evaluation:** Detection expects "Yes" to mark `Detection Accuracy` as correct; localization rewards matching the targeted service and reports `Localization Accuracy`, `success`, and subset information.【F:aiopslab/orchestrator/problems/misconfig_app/misconfig_app_variant.py†L117-L179】

## TiDB Operator – Control Plane Misoperations

### Operator Misoperation Detection & Localization
- **Variant knobs:** Configuration variants sweep misoperation type, extreme replica counts, toleration effects, security context user IDs, update strategies, and storage classes to probe a wide envelope of operator mistakes.【F:aiopslab/orchestrator/problems/operator_misoperation/operator_misoperation_variant.py†L23-L63】
- **Fault model:** Depending on the active `fault_type`, the variant triggers the corresponding `K8SOperatorFaultInjector._inject` routine with descriptive logging for curriculum analysis.【F:aiopslab/orchestrator/problems/operator_misoperation/operator_misoperation_variant.py†L101-L125】
- **Evaluation:** Detection keeps the "Yes"/"No" contract, while localization compares predicted custom resources to the ground truth and surfaces accuracy plus `success` metadata.【F:aiopslab/orchestrator/problems/operator_misoperation/operator_misoperation_variant.py†L147-L221】

## Social Network – Scaling and Routing Faults

### Scale Pod Detection & Localization
- **Variant knobs:** The service generator cycles through the Social Network frontend, backend, cache, and data services to test scaling competence across domains.【F:aiopslab/orchestrator/problems/scale_pod/scale_pod_variant.py†L23-L65】
- **Fault model:** Variants call `VirtualizationFaultInjector._inject` with `scale_pods_to_zero`, effectively scaling the chosen service to zero replicas.【F:aiopslab/orchestrator/problems/scale_pod/scale_pod_variant.py†L95-L112】
- **Evaluation:** Detection relies on the binary "Yes" submission, and localization reuses the accuracy plus success bookkeeping pattern established above.【F:aiopslab/orchestrator/problems/scale_pod/scale_pod_variant.py†L118-L180】

### Kubernetes Target Port Misconfiguration Detection & Localization
- **Variant knobs:** Service selection spans the Social Network mesh while the base configuration keeps a default wrong port that agents can override through variants.【F:aiopslab/orchestrator/problems/k8s_target_port_misconfig/target_port_variant.py†L23-L54】
- **Fault model:** The `VirtualizationFaultInjector._inject` call introduces the misconfigured target port for the active service list.【F:aiopslab/orchestrator/problems/k8s_target_port_misconfig/target_port_variant.py†L93-L114】
- **Evaluation:** Detection again expects "Yes", and localization measures accuracy for the faulty service along with boolean success diagnostics.【F:aiopslab/orchestrator/problems/k8s_target_port_misconfig/target_port_variant.py†L120-L183】

These summaries provide a quick reference to the diversity of variant knobs and evaluation lenses available, enabling practitioners to design curricula that systematically cover network, infrastructure, and control-plane fault modes.
