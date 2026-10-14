"""Installed Rust engine plus explicitly registered Scheme qualification fixtures."""
from pathlib import Path
from ascent import Engine

ROOT = Path(__file__).resolve().parents[2]


def module_engine():
    engine = Engine()
    source = ROOT / 't/qualification/evidence-api-module.ss'
    engine.register_module(':gerbil-ascent/t/qualification/evidence-api-module',
                           source.read_text(), trusted=True)
    return engine
