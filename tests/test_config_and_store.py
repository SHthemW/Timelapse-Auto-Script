from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from timelapse_manager.config import ConfigManager
from timelapse_manager.errors import ConfigError
from timelapse_manager.paths import AppPaths
from timelapse_manager.presets import PRESET_DESCRIPTIONS
from timelapse_manager.task_store import TaskStore


class ConfigAndStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.manager = ConfigManager(AppPaths.discover(self.root))
        self.manager.ensure()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_defaults_are_valid_and_cross_platform(self) -> None:
        loaded = self.manager.load()
        self.assertEqual(loaded.project["schema_version"], 1)
        self.assertTrue(loaded.auto_root.is_absolute())
        self.assertEqual(loaded.webhook["enabled"], False)

    def test_project_yaml_roundtrip(self) -> None:
        text = self.manager.read_text("project").replace(
            "capture_interval_seconds: 6", "capture_interval_seconds: 8"
        )
        self.manager.save_text("project", text)
        self.assertEqual(self.manager.load().project["capture_interval_seconds"], 8)

    def test_invalid_schedule_is_rejected(self) -> None:
        text = self.manager.read_text("project").replace(
            "start_at: '16:00'", "start_at: '08:00'"
        )
        with self.assertRaises(ConfigError):
            self.manager.save_text("project", text)

    def test_all_presets_can_be_created_before_manual_configuration(self) -> None:
        store = TaskStore(self.manager.load())
        for preset in PRESET_DESCRIPTIONS:
            task = store.create(preset, preset)
            self.assertEqual(store.load(task["id"])["preset"], preset)
        self.assertEqual(len(store.list_definitions()), len(PRESET_DESCRIPTIONS))


if __name__ == "__main__":
    unittest.main()
