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

import random
from typing import Dict

import pytest

from aiopslab.orchestrator.tasks.variant_task import VariantTask
from aiopslab.orchestrator.variant_generator import (
    ConfigVariantGenerator,
    CompositeVariantGenerator,
    NumericVariantGenerator,
    PortMisconfigVariantGenerator,
    ReplicaVariantGenerator,
    ServiceVariantGenerator,
)


class StubKubeCtl:
    def __init__(self, *args, **kwargs):
        pass

    def __getattr__(self, name):
        def method(*args, **kwargs):
            return None

        return method


@pytest.fixture(autouse=True)
def stub_kubectl(monkeypatch):
    monkeypatch.setattr("aiopslab.orchestrator.tasks.base.KubeCtl", StubKubeCtl)


class DummyVariantTask(VariantTask):
    def __init__(self, generator):
        super().__init__(generator)
        for key, value in generator.base_config.items():
            setattr(self, key, value)

    def get_task_description(self):
        return ""

    def get_instructions(self):
        return ""

    def get_available_actions(self):
        return []

    def perform_action(self, action_name, *args, **kwargs):
        raise NotImplementedError


def _assert_reset_to_base(generator, variant_overrides: Dict[str, object]):
    task = DummyVariantTask(generator)
    task.apply_variant(variant_overrides)

    for key, value in variant_overrides.items():
        assert getattr(task, key) == value

    task.reset_to_base()

    for key, value in generator.base_config.items():
        assert getattr(task, key) == value


def test_port_misconfig_generator_unique_and_reset():
    base_config = {"wrong_port": 9000}
    generator = PortMisconfigVariantGenerator(base_config.copy())
    random.seed(0)
    variants = generator.generate_variants(5)

    ports = {variant["wrong_port"] for variant in variants}
    assert len(ports) == len(variants)
    assert generator.base_config["wrong_port"] == 9000

    reset_generator = PortMisconfigVariantGenerator(base_config.copy())
    first_variant = reset_generator.generate_variants(1)[0]
    _assert_reset_to_base(reset_generator, first_variant)


def test_service_variant_generator_unique_and_reset():
    base_config = {"faulty_service": "user"}
    services = ["user", "geo", "profile", "search"]
    generator = ServiceVariantGenerator(base_config.copy(), services)
    random.seed(1)
    variants = generator.generate_variants(3)

    selected = {variant["faulty_service"] for variant in variants}
    assert len(selected) == len(variants)
    assert generator.base_config["faulty_service"] == "user"

    reset_generator = ServiceVariantGenerator(base_config.copy(), services)
    first_variant = reset_generator.generate_variants(1)[0]
    _assert_reset_to_base(reset_generator, first_variant)


def test_replica_variant_generator_unique_and_reset():
    base_config = {"replica_count": 3}
    generator = ReplicaVariantGenerator(base_config.copy())
    variants = generator.generate_variants(4)

    counts = [variant["replica_count"] for variant in variants]
    assert len(set(counts)) == len(counts)

    reset_generator = ReplicaVariantGenerator(base_config.copy())
    variant = reset_generator.generate_variants(1)[0]
    _assert_reset_to_base(reset_generator, variant)


def test_config_variant_generator_unique_and_reset():
    base_config = {"faulty_service": "geo", "config_type": "env"}
    config_variants = {
        "faulty_service": ["geo", "profile", "rate"],
        "config_type": ["env", "port", "memory"],
    }
    generator = ConfigVariantGenerator(base_config.copy(), config_variants)
    variants = generator.generate_variants(5)

    combos = {tuple(sorted(variant.items())) for variant in variants}
    assert len(combos) == len(variants)

    reset_generator = ConfigVariantGenerator(base_config.copy(), config_variants)
    variant = reset_generator.generate_variants(1)[0]
    _assert_reset_to_base(reset_generator, variant)


def test_numeric_variant_generator_unique_and_reset():
    base_config = {"loss_rate": 0.1}
    values = [0.05, 0.1, 0.2, 0.3]
    generator = NumericVariantGenerator(base_config.copy(), "loss_rate", values=values)
    variants = generator.generate_variants(4)

    magnitudes = [variant["loss_rate"] for variant in variants]
    assert len(set(magnitudes)) == len(magnitudes)

    reset_generator = NumericVariantGenerator(base_config.copy(), "loss_rate", values=values)
    variant = reset_generator.generate_variants(1)[0]
    _assert_reset_to_base(reset_generator, variant)


def test_composite_variant_generator_unique_and_reset(monkeypatch):
    base_config = {"faulty_service": "user", "loss_rate": 0.1}
    services = ["user", "geo"]
    values = [0.1, 0.2]

    service_generator = ServiceVariantGenerator(base_config.copy(), services)
    numeric_generator = NumericVariantGenerator(base_config.copy(), "loss_rate", values=values)

    composite = CompositeVariantGenerator([service_generator, numeric_generator])

    monkeypatch.setattr(
        "aiopslab.orchestrator.variant_generator.random.choice",
        lambda options: options[0],
    )

    variants = composite.generate_variants(4)
    combos = {tuple(sorted(variant.items())) for variant in variants}
    assert len(combos) == len(variants)

    reset_generator = CompositeVariantGenerator(
        [
            ServiceVariantGenerator(base_config.copy(), services),
            NumericVariantGenerator(base_config.copy(), "loss_rate", values=values),
        ]
    )
    override = {"faulty_service": "geo", "loss_rate": 0.3}
    _assert_reset_to_base(reset_generator, override)
