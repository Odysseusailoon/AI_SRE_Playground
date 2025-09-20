import pytest
import sys
from pathlib import Path

sys.path.append(str(Path(__file__).resolve().parents[2]))

import atexit

CONFIG_PATH = Path(__file__).resolve().parents[2] / "aiopslab" / "config.yml"
if not CONFIG_PATH.exists():
    example = CONFIG_PATH.with_suffix('.yml.example')
    if example.exists():
        CONFIG_PATH.write_text(example.read_text())
    else:
        CONFIG_PATH.write_text('data_dir: data\nprint_session: false\n')
    atexit.register(lambda path=CONFIG_PATH: path.unlink(missing_ok=True))

from aiopslab.orchestrator.tasks import AnalysisTask, MitigationTask


class StubKubeCtl:
    def __init__(self, *args, **kwargs):
        pass

    def __getattr__(self, name):
        def method(*args, **kwargs):
            return None

        return method


class StubApp:
    def __init__(self, *args, **kwargs):
        self.namespace = "test-ns"
        self.helm_configs = {}

    def get_app_summary(self):
        return "stub app"

    def delete(self):
        return None

    def deploy(self):
        return None

    def cleanup(self):
        return None


class StubWrk:
    def __init__(self, *args, **kwargs):
        self.calls = []

    def start_workload(self, *args, **kwargs):
        self.calls.append((args, kwargs))


@pytest.fixture(autouse=True)
def stub_task_kubectl(monkeypatch):
    monkeypatch.setattr("aiopslab.orchestrator.tasks.base.KubeCtl", StubKubeCtl)


def test_network_loss_detection_injects_selected_service(monkeypatch):
    from aiopslab.orchestrator.problems.network_loss import network_loss_variant as network_loss

    class RecordingLossInjector:
        def __init__(self, namespace):
            self.namespace = namespace
            self.calls = []

        def inject_network_loss(self, services):
            self.calls.append(list(services))

        def recover_network_loss(self):
            self.calls.append(("recover", None))

    monkeypatch.setattr(network_loss, "HotelReservation", StubApp)
    monkeypatch.setattr(network_loss, "KubeCtl", StubKubeCtl)
    monkeypatch.setattr(network_loss, "Wrk", StubWrk)
    monkeypatch.setattr(network_loss, "SymptomFaultInjector", RecordingLossInjector)

    variant = network_loss.NetworkLossVariantDetection(enable_variants=True)
    next_variant = variant.get_next_variant()
    if next_variant:
        variant.apply_variant(next_variant)

    variant.inject_fault()
    assert variant.injector.calls[-1] == [variant.faulty_service]


def test_container_kill_localization_targets_service_and_container(monkeypatch):
    from aiopslab.orchestrator.problems.container_kill import container_kill_variant as container_kill

    class RecordingContainerInjector:
        def __init__(self, namespace):
            self.namespace = namespace
            self.calls = []

        def inject_container_kill(self, service, container):
            self.calls.append((service, container))

        def recover_container_kill(self):
            self.calls.append(("recover", None))

    monkeypatch.setattr(container_kill, "HotelReservation", StubApp)
    monkeypatch.setattr(container_kill, "KubeCtl", StubKubeCtl)
    monkeypatch.setattr(container_kill, "Wrk", StubWrk)
    monkeypatch.setattr(container_kill, "SymptomFaultInjector", RecordingContainerInjector)

    variant = container_kill.ContainerKillVariantLocalization(enable_variants=True)
    next_variant = variant.get_next_variant()
    if next_variant:
        variant.apply_variant(next_variant)
    else:
        variant.apply_variant({"faulty_service": "profile", "faulty_container": "hotel-reserv-profile"})

    variant.inject_fault()
    assert variant.symptom_injector.calls[-1] == (variant.faulty_service, variant.faulty_container)


def test_operator_misoperation_analysis_injects_fault_type(monkeypatch):
    from aiopslab.orchestrator.problems.operator_misoperation import operator_misoperation_variant as operator_variant

    class StubTiDBCluster(StubApp):
        pass

    class RecordingOperatorInjector:
        def __init__(self, namespace):
            self.namespace = namespace
            self.calls = []

        def _inject(self, fault_type):
            self.calls.append(fault_type)

        def _recover(self, fault_type):
            self.calls.append(("recover", fault_type))

    monkeypatch.setattr(operator_variant, "TiDBCluster", StubTiDBCluster)
    monkeypatch.setattr(operator_variant, "K8SOperatorFaultInjector", RecordingOperatorInjector)

    class AnalysisVariant(operator_variant.K8SOperatorMisoperationVariantBase, AnalysisTask):
        def __init__(self, fault_type="overload_replicas"):
            operator_variant.K8SOperatorMisoperationVariantBase.__init__(
                self, fault_type=fault_type, enable_variants=True
            )
            AnalysisTask.__init__(self, self.app)

    variant = AnalysisVariant()
    variant.apply_variant({"fault_type": "security_context_fault"})

    variant.inject_fault()
    assert variant.injector.calls[-1] == "security_context_fault"


def test_pod_kill_mitigation_passes_duration_and_service(monkeypatch):
    from aiopslab.orchestrator.problems.pod_kill import pod_kill_variant as pod_kill

    class RecordingPodKillInjector:
        def __init__(self, namespace):
            self.namespace = namespace
            self.calls = []

        def _inject(self, fault_type, microservices, duration):
            self.calls.append({
                "fault_type": fault_type,
                "microservices": list(microservices),
                "duration": duration,
            })

        def _recover(self, fault_type):
            self.calls.append(("recover", fault_type))

    monkeypatch.setattr(pod_kill, "HotelReservation", StubApp)
    monkeypatch.setattr(pod_kill, "KubeCtl", StubKubeCtl)
    monkeypatch.setattr(pod_kill, "Wrk", StubWrk)
    monkeypatch.setattr(pod_kill, "SymptomFaultInjector", RecordingPodKillInjector)

    class PodKillMitigation(pod_kill.PodKillVariantBase, MitigationTask):
        def __init__(self, faulty_service="user", duration="100s"):
            pod_kill.PodKillVariantBase.__init__(
                self, faulty_service=faulty_service, duration=duration, enable_variants=True
            )
            MitigationTask.__init__(self, self.app)

    variant = PodKillMitigation()
    variant.apply_variant({"faulty_service": "reservation", "duration": "300s"})

    variant.inject_fault()
    call = variant.injector.calls[-1]
    assert call["fault_type"] == "pod_kill"
    assert call["microservices"] == [variant.faulty_service]
    assert call["duration"] == variant.duration
