"""Task-level YAML presets."""

from __future__ import annotations

from copy import deepcopy
from typing import Any

from timelapse_manager.errors import ConfigError
from timelapse_manager.io_utils import now_iso


PRESET_DESCRIPTIONS = {
    "scheduled_once": "自动选择下一个清晨或黄昏时间段，仅执行一次",
    "scheduled_loop": "按清晨/黄昏预设永久循环，失败后自动重试",
    "eternal": "持续拍摄，按完整曝光组分批归档并串行处理",
    "manual": "手动指定日期、时段和工作目录的单次任务",
}

BASE_TASK: dict[str, Any] = {
    "schema_version": 1,
    "id": "",
    "name": "",
    "preset": "manual",
    "created_at": "",
    "capture": {
        "work_dir": None,
        "start_date": None,
        "start_at": None,
        "end_date": None,
        "end_at": None,
        "interval_seconds": None,
    },
    "processing": {"enabled": True},
    "cleanup": {
        "enabled": False,
        "keep_directories": ["hdr_enfuse", "hdr_video"],
        "delete_incomplete_groups": False,
        "on_failure": False,
    },
    "retry": {"enabled": False, "delay_seconds": None},
    "eternal": {"batch_groups": None, "images_per_group": None, "state_dir": None},
    "environment": {},
}


def create_preset(task_id: str, name: str, preset: str) -> dict[str, Any]:
    if preset not in PRESET_DESCRIPTIONS:
        raise ConfigError(f"未知预设: {preset}")
    task = deepcopy(BASE_TASK)
    task.update(
        {
            "id": task_id,
            "name": name.strip() or task_id,
            "preset": preset,
            "created_at": now_iso(),
        }
    )
    if preset in {"scheduled_once", "scheduled_loop"}:
        task["cleanup"]["enabled"] = True
        task["cleanup"]["delete_incomplete_groups"] = True
        task["cleanup"]["on_failure"] = True
    if preset == "scheduled_loop":
        task["retry"]["enabled"] = True
    if preset == "eternal":
        task["cleanup"]["enabled"] = True
        task["cleanup"]["delete_incomplete_groups"] = True
        task["cleanup"]["on_failure"] = True
        task["retry"]["enabled"] = True
    return task


def validate_task(task: dict[str, Any], *, for_start: bool = False) -> None:
    for key in ("id", "name", "preset"):
        if not isinstance(task.get(key), str) or not task[key].strip():
            raise ConfigError(f"任务字段 {key} 不能为空")
    if task["preset"] not in PRESET_DESCRIPTIONS:
        raise ConfigError(f"未知预设: {task['preset']}")
    if not isinstance(task.get("capture"), dict):
        raise ConfigError("任务 capture 必须是映射")
    if not isinstance(task.get("processing"), dict):
        raise ConfigError("任务 processing 必须是映射")
    if not isinstance(task.get("cleanup"), dict):
        raise ConfigError("任务 cleanup 必须是映射")
    if not isinstance(task.get("retry"), dict):
        raise ConfigError("任务 retry 必须是映射")
    if not isinstance(task.get("environment"), dict):
        raise ConfigError("任务 environment 必须是映射")

    interval = task["capture"].get("interval_seconds")
    if interval is not None and (
        isinstance(interval, bool)
        or not isinstance(interval, (int, float))
        or interval <= 0
    ):
        raise ConfigError("capture.interval_seconds 必须为空或大于 0")
    if not isinstance(task["processing"].get("enabled"), bool):
        raise ConfigError("processing.enabled 必须是 true 或 false")

    if task["preset"] == "manual" and for_start:
        required = ("work_dir", "start_date", "start_at", "end_date", "end_at")
        missing = [key for key in required if not task["capture"].get(key)]
        if missing:
            raise ConfigError(
                "手动任务开始前必须设置: " + ", ".join(f"capture.{x}" for x in missing)
            )

    cleanup = task["cleanup"]
    for key in ("enabled", "delete_incomplete_groups", "on_failure"):
        if not isinstance(cleanup.get(key), bool):
            raise ConfigError(f"cleanup.{key} 必须是 true 或 false")
    keep = cleanup.get("keep_directories")
    if not isinstance(keep, list) or not all(
        isinstance(item, str) and item for item in keep
    ):
        raise ConfigError("cleanup.keep_directories 必须是非空字符串列表")

    retry = task["retry"]
    if not isinstance(retry.get("enabled"), bool):
        raise ConfigError("retry.enabled 必须是 true 或 false")
    retry_delay = retry.get("delay_seconds")
    if retry_delay is not None and (
        isinstance(retry_delay, bool)
        or not isinstance(retry_delay, (int, float))
        or retry_delay < 0
    ):
        raise ConfigError("retry.delay_seconds 必须为空或大于等于 0")

    eternal = task.get("eternal")
    if not isinstance(eternal, dict):
        raise ConfigError("任务 eternal 必须是映射")
    for key in ("batch_groups", "images_per_group"):
        value = eternal.get(key)
        if value is not None and (
            isinstance(value, bool) or not isinstance(value, int) or value < 1
        ):
            raise ConfigError(f"eternal.{key} 必须为空或为正整数")
    state_dir = eternal.get("state_dir")
    if state_dir is not None and (
        not isinstance(state_dir, str) or not state_dir.strip()
    ):
        raise ConfigError("eternal.state_dir 必须为空或为非空路径")

    env = task["environment"]
    if not all(
        isinstance(key, str) and isinstance(value, (str, int, float, bool))
        for key, value in env.items()
    ):
        raise ConfigError("environment 的键必须是字符串，值必须是标量")
