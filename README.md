# Timelapse Manager

Timelapse Manager 是原 shell 自动化脚本的跨平台 Python 重构版。它把拍摄、后期处理、持久化状态和进程控制放在无界面的核心中，CLI 与 GUI 只是同一套管理服务的两个入口。

支持 Windows、macOS 和 Linux。任务关闭 GUI 后仍会继续运行，重新打开 GUI 或在另一个终端执行 CLI 可以继续查看和控制。

## 功能

- 任务列表持久化展示名称、预设、状态、当前阶段、工作进程 PID 和启动时间。
- 进程列表展示每个任务工作进程及其 `camera-timelapse`、Bracketlapse 子进程。
- 支持启动、立即收尾、当前任务/整批后收尾、强制停止、重启和删除。
- 项目级配置继续使用 `config/auto_timelapse.yaml` 和 `config/webhook.yaml`。
- 每个任务使用独立的 `config/tasks/<task-id>.yaml`，清理策略等细节可以逐任务覆盖。
- GUI 可读取、校验并写回项目 YAML、webhook YAML 和任务 YAML；从外部修改后也可重新读取。
- 支持 webhook 文本与图片通知、磁盘空间告警、日志查看和异常状态恢复。
- 仅提供 debug portable 打包机制，不生成 release 包。

## 内置预设

| 预设 | 对应旧入口 | 行为 |
| --- | --- | --- |
| `scheduled_once` | `auto_timelapse.sh` | 手动启动后，自动选择下一个清晨或黄昏时间段并执行一次 |
| `scheduled_loop` | `auto_timelapse_loop.sh` | 手动启动后，在清晨和黄昏任务间永久循环，失败后重试 |
| `eternal` | `start_timelapse_eternal.sh` | 手动启动后持续拍摄，按完整曝光组分批归档并串行执行后期 |
| `manual` | 新增 | 日期、时间、工作目录、清理策略等全部由任务 YAML 指定 |

所有任务都只会由用户手动启动。创建任务、编辑 YAML 或打开 GUI 都不会自动开始拍摄。

## 环境要求

- Python 3.10 或更高版本。
- `camera-timelapse` 已安装并可从 PATH 调用，或在 YAML 中配置其绝对路径。
- `brackerlapse` 或 `bracketlapse` 已安装并可调用。
- Linux GUI 需要系统提供 Tk，例如 Debian/Ubuntu 的 `python3-tk`。

安装 Python 依赖：

```bash
python -m pip install -r requirements.txt
```

如需以可编辑包方式安装并获得 `timelapse-manager` 命令：

```bash
python -m pip install -e .
```

## 快速开始

初始化默认配置和运行目录：

```bash
python timelapse.py init
```

首次初始化会生成以下两个实际配置文件，它们默认被 Git 忽略：

- `config/auto_timelapse.yaml`
- `config/webhook.yaml`

请先设置清晨、黄昏时间和外部命令，再执行自测：

```bash
python timelapse.py config validate
python timelapse.py self-test
```

未安装相机或后期命令时，普通自测会显示 `WARN`，但内部检查仍可通过。需要把外部命令缺失也视为失败时使用：

```bash
python timelapse.py self-test --full
```

启动 GUI：

```bash
python timelapse.py gui
```

GUI 启动后可在“任务”页创建预设任务，双击任务编辑进程级 YAML，保存后再手动点击“启动”。

## CLI 管理

列出预设与任务：

```bash
python timelapse.py preset list
python timelapse.py task list
python timelapse.py task list --json
```

创建并启动单次定时任务：

```bash
python timelapse.py task create --name "今日自动拍摄" --preset scheduled_once
python timelapse.py task start <task-id>
```

也可以创建后立即手动启动：

```bash
python timelapse.py run --name "清晨和黄昏循环" --preset scheduled_loop
```

创建手动任务时必须提供完整的起止日期、时间和工作目录：

```bash
python timelapse.py task create \
  --name "手动测试" \
  --preset manual \
  --work-dir ./output/manual \
  --start-date 2026-07-22 \
  --start-at 03:00 \
  --end-date 2026-07-22 \
  --end-at 09:00 \
  --interval 6
```

查看任务详情、日志和受控进程：

```bash
python timelapse.py task show <task-id>
python timelapse.py task logs <task-id> --follow
python timelapse.py process list
python timelapse.py process list --json
```

控制任务：

```bash
python timelapse.py task finish <task-id>
python timelapse.py task finish-after-current <task-id>
python timelapse.py task stop <task-id>
python timelapse.py task restart <task-id>
```

控制语义如下：

- `finish`：立即停止当前相机拍摄，忽略不完整曝光组，完成可用素材的后期与导出后结束。
- `finish-after-current`：单次/循环任务在当前时段完成后结束；永续任务拍满当前配置的整批组数后结束。
- `stop`：强制终止工作进程和全部受控子进程，未完成的永续队列留待下次恢复。

需要前台运行并直接在当前终端观察日志时：

```bash
python timelapse.py task start <task-id> --foreground
```

## 配置

项目配置示例见 `config/auto_timelapse.example.yaml`。旧版已有的以下键保持兼容：

- `auto_root`
- `capture_interval_seconds`
- `watch_quiet_seconds`
- `disk_space_warning_threshold_gb`
- `morning.start_at` / `morning.end_at`
- `dusk.start_at` / `dusk.end_at`

外部命令和 Python 运行时配置位于新增的 `commands`、`runtime`、`eternal` 节点。

可从 CLI 修改任意点分隔字段：

```bash
python timelapse.py config set morning.start_at "'04:00'"
python timelapse.py config set disk_space_warning_threshold_gb 50
python timelapse.py config set url "'https://example.invalid/webhook'" --kind webhook
python timelapse.py config set enabled true --kind webhook
```

环境变量 `AUTO_TIMELAPSE_CONFIG` 和 `AUTO_TIMELAPSE_WEBHOOK_CONFIG` 可以指定其他 YAML 路径。原脚本使用的 `AUTO_ROOT`、`AUTO_TIMELAPSE_ROOT`、`CAPTURE_INTERVAL_SECONDS`、`WATCH_QUIET_SECONDS`、清晨与黄昏时间变量也继续支持运行时覆盖。

### 任务级 YAML

每个任务都有独立配置。常用字段如下：

```yaml
capture:
  work_dir: null
  start_date: null
  start_at: null
  end_date: null
  end_at: null
  interval_seconds: null
processing:
  enabled: true
cleanup:
  enabled: true
  keep_directories:
    - hdr_enfuse
    - hdr_video
  delete_incomplete_groups: true
  on_failure: true
retry:
  enabled: true
  delay_seconds: null
eternal:
  batch_groups: 2000
  images_per_group: 3
  state_dir: null
environment: {}
```

`null` 表示继承项目级配置。纯手动任务默认关闭清理，预设任务默认沿用旧脚本行为，仅保留 `hdr_enfuse` 和 `hdr_video`。如果不希望处理失败时删除中间文件，应把该任务的 `cleanup.on_failure` 改为 `false`。

运行中的任务不允许修改任务 YAML，避免工作进程与界面看到不同配置。

## 状态与恢复

运行时数据默认位于 `.timelapse/`：

```text
.timelapse/
└── tasks/
    └── <task-id>/
        ├── state.json
        ├── task.log
        └── control/
```

状态写入使用临时文件、原子替换和跨进程写锁。进程校验同时比较 PID 和进程创建时间，避免 PID 被操作系统复用后误判。

永续任务使用 `<auto_root>/.eternal/` 保存暂存图片、归档清单和跨平台 YAML 队列。它不依赖 Unix FIFO、用户信号或符号链接，因此可在三端使用。处理失败的批次会进入 `*.failed.yaml`，下次启动自动重新入队。

## Debug 打包

打包只能在目标系统本机完成，PyInstaller 不支持从一个系统直接交叉编译另外两个系统。分别在 Windows、macOS 和 Linux 安装开发依赖后执行：

```bash
python -m pip install -r requirements-dev.txt
python scripts/build_debug.py
```

脚本只生成 console/debug/portable 包，并保存到：

```text
bin/Debug-Archives/TimelapseManager-<win|mac|linux>-debug-portable-<yymmdd-hhmmss>.zip
```

解压后可从命令行执行 `TimelapseManager init`、`TimelapseManager self-test` 和 `TimelapseManager gui`。macOS/Linux 下文件名不带 `.exe`。

## 开发与测试

```bash
python -m pip install -e .
python -m unittest discover -s tests -v
python timelapse.py self-test
```

测试套件包含无需真实相机的模拟 `camera-timelapse` 和 Bracketlapse。它会实际创建后台工作进程，验证单次预设、永续分批、状态持久化、优雅收尾与清理行为。

原 shell 文件暂时保留，方便已有环境迁移和行为对照；新的跨平台主入口是 `timelapse.py` 或安装后的 `timelapse-manager`。
