"""Tk front end for the headless Timelapse Manager service."""

from __future__ import annotations

import os
import subprocess
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk
from typing import Callable

from timelapse_manager.presets import PRESET_DESCRIPTIONS
from timelapse_manager.service import ManagerService


class YamlEditorDialog(tk.Toplevel):
    def __init__(
        self,
        parent: tk.Misc,
        title: str,
        load_text: Callable[[], str],
        save_text: Callable[[str], object],
        on_saved: Callable[[], None] | None = None,
    ):
        super().__init__(parent)
        self.title(title)
        self.geometry("780x680")
        self.minsize(560, 400)
        self.load_text = load_text
        self.save_text = save_text
        self.on_saved = on_saved
        self.transient(parent.winfo_toplevel())

        frame = ttk.Frame(self, padding=10)
        frame.pack(fill=tk.BOTH, expand=True)
        self.text = tk.Text(frame, wrap=tk.NONE, undo=True, font=("TkFixedFont", 10))
        vertical = ttk.Scrollbar(frame, orient=tk.VERTICAL, command=self.text.yview)
        horizontal = ttk.Scrollbar(frame, orient=tk.HORIZONTAL, command=self.text.xview)
        self.text.configure(yscrollcommand=vertical.set, xscrollcommand=horizontal.set)
        self.text.grid(row=0, column=0, sticky="nsew")
        vertical.grid(row=0, column=1, sticky="ns")
        horizontal.grid(row=1, column=0, sticky="ew")
        frame.rowconfigure(0, weight=1)
        frame.columnconfigure(0, weight=1)

        buttons = ttk.Frame(frame)
        buttons.grid(row=2, column=0, columnspan=2, sticky="ew", pady=(10, 0))
        ttk.Button(buttons, text="重新读取", command=self.reload).pack(side=tk.LEFT)
        ttk.Button(buttons, text="保存", command=self.save).pack(side=tk.RIGHT)
        ttk.Button(buttons, text="关闭", command=self.destroy).pack(
            side=tk.RIGHT, padx=(0, 8)
        )
        self.reload()

    def reload(self) -> None:
        try:
            value = self.load_text()
        except Exception as exc:
            messagebox.showerror("读取失败", str(exc), parent=self)
            return
        self.text.delete("1.0", tk.END)
        self.text.insert("1.0", value)
        self.text.edit_modified(False)

    def save(self) -> None:
        try:
            self.save_text(self.text.get("1.0", "end-1c"))
        except Exception as exc:
            messagebox.showerror("保存失败", str(exc), parent=self)
            return
        self.text.edit_modified(False)
        if self.on_saved:
            self.on_saved()
        messagebox.showinfo("保存成功", "YAML 已校验并保存。", parent=self)


class NewTaskDialog(tk.Toplevel):
    def __init__(self, parent: tk.Misc):
        super().__init__(parent)
        self.title("新建任务")
        self.resizable(False, False)
        self.transient(parent.winfo_toplevel())
        self.result: tuple[str, str] | None = None
        self.name_value = tk.StringVar(value="延时摄影任务")
        self.preset_value = tk.StringVar(value="scheduled_once")

        frame = ttk.Frame(self, padding=16)
        frame.pack(fill=tk.BOTH, expand=True)
        ttk.Label(frame, text="任务名称").grid(row=0, column=0, sticky="w", pady=5)
        name_entry = ttk.Entry(frame, textvariable=self.name_value, width=42)
        name_entry.grid(row=0, column=1, sticky="ew", pady=5)
        ttk.Label(frame, text="任务预设").grid(row=1, column=0, sticky="w", pady=5)
        preset = ttk.Combobox(
            frame,
            textvariable=self.preset_value,
            values=tuple(PRESET_DESCRIPTIONS),
            state="readonly",
            width=39,
        )
        preset.grid(row=1, column=1, sticky="ew", pady=5)
        self.description = ttk.Label(frame, wraplength=360)
        self.description.grid(row=2, column=0, columnspan=2, sticky="w", pady=(4, 12))
        preset.bind("<<ComboboxSelected>>", lambda _event: self._update_description())
        self._update_description()

        buttons = ttk.Frame(frame)
        buttons.grid(row=3, column=0, columnspan=2, sticky="e")
        ttk.Button(buttons, text="取消", command=self.destroy).pack(side=tk.RIGHT)
        ttk.Button(buttons, text="创建", command=self._submit).pack(
            side=tk.RIGHT, padx=(0, 8)
        )
        self.bind("<Return>", lambda _event: self._submit())
        self.bind("<Escape>", lambda _event: self.destroy())
        name_entry.focus_set()
        self.grab_set()

    def _update_description(self) -> None:
        self.description.configure(text=PRESET_DESCRIPTIONS[self.preset_value.get()])

    def _submit(self) -> None:
        name = self.name_value.get().strip()
        if not name:
            messagebox.showwarning("名称为空", "请输入任务名称。", parent=self)
            return
        self.result = (name, self.preset_value.get())
        self.destroy()


class TimelapseApp:
    REFRESH_MS = 1500

    def __init__(self, root: tk.Tk, service: ManagerService):
        self.root = root
        self.service = service
        self.root.title("Timelapse Manager - Debug")
        self.root.geometry("1220x780")
        self.root.minsize(900, 600)
        self.root.protocol("WM_DELETE_WINDOW", self.close)
        self._closed = False
        self._busy = 0
        self.status_value = tk.StringVar(value="就绪")
        self._build_style()
        self._build_ui()
        self.refresh_all()
        self.root.after(self.REFRESH_MS, self._periodic_refresh)

    def _build_style(self) -> None:
        style = ttk.Style(self.root)
        if "clam" in style.theme_names():
            style.theme_use("clam")
        style.configure("Treeview", rowheight=26)
        style.configure("Treeview.Heading", font=("TkDefaultFont", 10, "bold"))

    def _build_ui(self) -> None:
        outer = ttk.Frame(self.root, padding=(10, 10, 10, 6))
        outer.pack(fill=tk.BOTH, expand=True)
        header = ttk.Frame(outer)
        header.pack(fill=tk.X, pady=(0, 8))
        ttk.Label(
            header, text="Timelapse Manager", font=("TkDefaultFont", 16, "bold")
        ).pack(side=tk.LEFT)
        ttk.Label(header, text=f"项目：{self.service.paths.root}").pack(side=tk.RIGHT)

        self.notebook = ttk.Notebook(outer)
        self.notebook.pack(fill=tk.BOTH, expand=True)
        self.tasks_tab = ttk.Frame(self.notebook, padding=8)
        self.process_tab = ttk.Frame(self.notebook, padding=8)
        self.config_tab = ttk.Frame(self.notebook, padding=8)
        self.logs_tab = ttk.Frame(self.notebook, padding=8)
        self.notebook.add(self.tasks_tab, text="任务")
        self.notebook.add(self.process_tab, text="进程")
        self.notebook.add(self.config_tab, text="项目配置")
        self.notebook.add(self.logs_tab, text="日志")
        self.notebook.bind("<<NotebookTabChanged>>", lambda _event: self._tab_changed())

        self._build_tasks_tab()
        self._build_process_tab()
        self._build_config_tab()
        self._build_logs_tab()
        ttk.Separator(outer).pack(fill=tk.X, pady=(6, 4))
        ttk.Label(outer, textvariable=self.status_value, anchor="w").pack(fill=tk.X)

    def _build_tasks_tab(self) -> None:
        columns = ("id", "name", "preset", "status", "phase", "pid", "started")
        self.task_tree = ttk.Treeview(
            self.tasks_tab, columns=columns, show="headings", selectmode="browse"
        )
        headings = {
            "id": "任务 ID",
            "name": "名称",
            "preset": "预设",
            "status": "状态",
            "phase": "当前阶段",
            "pid": "工作 PID",
            "started": "启动时间",
        }
        widths = {
            "id": 190,
            "name": 150,
            "preset": 120,
            "status": 90,
            "phase": 240,
            "pid": 90,
            "started": 170,
        }
        for column in columns:
            self.task_tree.heading(column, text=headings[column])
            self.task_tree.column(
                column,
                width=widths[column],
                minwidth=70,
                stretch=column in {"name", "phase"},
            )
        scrollbar = ttk.Scrollbar(
            self.tasks_tab, orient=tk.VERTICAL, command=self.task_tree.yview
        )
        self.task_tree.configure(yscrollcommand=scrollbar.set)
        self.task_tree.grid(row=0, column=0, sticky="nsew")
        scrollbar.grid(row=0, column=1, sticky="ns")
        self.tasks_tab.rowconfigure(0, weight=1)
        self.tasks_tab.columnconfigure(0, weight=1)
        self.task_tree.bind("<Double-1>", lambda _event: self.edit_task())
        self.task_tree.bind(
            "<<TreeviewSelect>>", lambda _event: self._selection_changed()
        )
        self.task_tree.tag_configure("failed", foreground="#b00020")
        self.task_tree.tag_configure("running", foreground="#006b2d")
        self.task_tree.tag_configure("finishing", foreground="#9a5b00")

        buttons = ttk.Frame(self.tasks_tab)
        buttons.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(8, 0))
        actions = (
            ("新建", self.create_task),
            ("编辑 YAML", self.edit_task),
            ("启动", self.start_task),
            ("立即收尾", lambda: self.control_task("finish_now")),
            ("当前任务/批次后收尾", lambda: self.control_task("finish_after_current")),
            ("强制停止", lambda: self.control_task("stop")),
            ("重启", self.restart_task),
            ("删除", self.delete_task),
            ("刷新", self.refresh_all),
        )
        for index, (label, command) in enumerate(actions):
            ttk.Button(buttons, text=label, command=command).pack(
                side=tk.LEFT, padx=(0 if index == 0 else 5, 0)
            )

    def _build_process_tab(self) -> None:
        columns = ("task", "role", "pid", "status", "started", "command")
        self.process_tree = ttk.Treeview(
            self.process_tab, columns=columns, show="headings", selectmode="browse"
        )
        headings = {
            "task": "任务",
            "role": "进程角色",
            "pid": "PID",
            "status": "状态",
            "started": "启动时间",
            "command": "命令",
        }
        widths = {
            "task": 190,
            "role": 210,
            "pid": 90,
            "status": 90,
            "started": 170,
            "command": 440,
        }
        for column in columns:
            self.process_tree.heading(column, text=headings[column])
            self.process_tree.column(
                column, width=widths[column], stretch=column == "command"
            )
        scrollbar = ttk.Scrollbar(
            self.process_tab, orient=tk.VERTICAL, command=self.process_tree.yview
        )
        self.process_tree.configure(yscrollcommand=scrollbar.set)
        self.process_tree.grid(row=0, column=0, sticky="nsew")
        scrollbar.grid(row=0, column=1, sticky="ns")
        self.process_tab.rowconfigure(0, weight=1)
        self.process_tab.columnconfigure(0, weight=1)
        buttons = ttk.Frame(self.process_tab)
        buttons.grid(row=1, column=0, columnspan=2, sticky="w", pady=(8, 0))
        ttk.Button(buttons, text="终止所选进程", command=self.stop_process).pack(
            side=tk.LEFT
        )
        ttk.Button(buttons, text="刷新", command=self.refresh_processes).pack(
            side=tk.LEFT, padx=5
        )

    def _build_config_tab(self) -> None:
        self.config_notebook = ttk.Notebook(self.config_tab)
        self.config_notebook.pack(fill=tk.BOTH, expand=True)
        self.config_editors: dict[str, tk.Text] = {}
        for kind, label in (
            ("project", "auto_timelapse.yaml"),
            ("webhook", "webhook.yaml"),
        ):
            frame = ttk.Frame(self.config_notebook, padding=6)
            self.config_notebook.add(frame, text=label)
            text = tk.Text(frame, wrap=tk.NONE, undo=True, font=("TkFixedFont", 10))
            vertical = ttk.Scrollbar(frame, orient=tk.VERTICAL, command=text.yview)
            horizontal = ttk.Scrollbar(frame, orient=tk.HORIZONTAL, command=text.xview)
            text.configure(yscrollcommand=vertical.set, xscrollcommand=horizontal.set)
            text.grid(row=0, column=0, sticky="nsew")
            vertical.grid(row=0, column=1, sticky="ns")
            horizontal.grid(row=1, column=0, sticky="ew")
            frame.rowconfigure(0, weight=1)
            frame.columnconfigure(0, weight=1)
            buttons = ttk.Frame(frame)
            buttons.grid(row=2, column=0, columnspan=2, sticky="ew", pady=(8, 0))
            ttk.Button(
                buttons,
                text="从磁盘重新读取",
                command=lambda value=kind: self.reload_config(value),
            ).pack(side=tk.LEFT)
            ttk.Button(
                buttons,
                text="打开所在目录",
                command=lambda value=kind: self.open_config_location(value),
            ).pack(side=tk.LEFT, padx=5)
            ttk.Button(
                buttons,
                text="校验并保存",
                command=lambda value=kind: self.save_config(value),
            ).pack(side=tk.RIGHT)
            self.config_editors[kind] = text
            self.reload_config(kind)

    def _build_logs_tab(self) -> None:
        top = ttk.Frame(self.logs_tab)
        top.pack(fill=tk.X, pady=(0, 6))
        ttk.Label(top, text="当前任务：").pack(side=tk.LEFT)
        self.log_task_value = tk.StringVar(value="")
        self.log_task_box = ttk.Combobox(
            top, textvariable=self.log_task_value, state="readonly", width=45
        )
        self.log_task_box.pack(side=tk.LEFT)
        self.log_task_box.bind(
            "<<ComboboxSelected>>", lambda _event: self.refresh_log()
        )
        ttk.Button(top, text="刷新", command=self.refresh_log).pack(
            side=tk.LEFT, padx=5
        )
        ttk.Button(top, text="打开日志目录", command=self.open_log_location).pack(
            side=tk.LEFT
        )
        self.log_text = tk.Text(
            self.logs_tab, wrap=tk.NONE, state=tk.DISABLED, font=("TkFixedFont", 10)
        )
        scrollbar = ttk.Scrollbar(
            self.logs_tab, orient=tk.VERTICAL, command=self.log_text.yview
        )
        self.log_text.configure(yscrollcommand=scrollbar.set)
        self.log_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

    def _selected_task_id(self) -> str | None:
        selected = self.task_tree.selection()
        return selected[0] if selected else None

    def _selection_changed(self) -> None:
        task_id = self._selected_task_id()
        if task_id:
            self.log_task_value.set(task_id)

    def create_task(self) -> None:
        dialog = NewTaskDialog(self.root)
        self.root.wait_window(dialog)
        if not dialog.result:
            return
        name, preset = dialog.result
        try:
            task = self.service.create_task(name, preset)
        except Exception as exc:
            messagebox.showerror("创建失败", str(exc), parent=self.root)
            return
        self.refresh_all(select=task["id"])
        self.edit_task(task["id"])

    def edit_task(self, task_id: str | None = None) -> None:
        target = task_id or self._selected_task_id()
        if not target:
            messagebox.showinfo("未选择任务", "请先选择一个任务。", parent=self.root)
            return
        YamlEditorDialog(
            self.root,
            f"编辑任务 YAML - {target}",
            lambda: self.service.store.read_text(target),
            lambda text: self.service.store.save_text(target, text),
            self.refresh_all,
        )

    def start_task(self) -> None:
        task_id = self._selected_task_id()
        if task_id:
            self._async_action("启动任务", lambda: self.service.start_task(task_id))

    def control_task(self, action: str) -> None:
        task_id = self._selected_task_id()
        if not task_id:
            return
        if action == "stop" and not messagebox.askyesno(
            "确认强制停止",
            "这会立即终止任务的全部受控子进程，是否继续？",
            parent=self.root,
        ):
            return
        self._async_action(
            "发送控制指令", lambda: self.service.request(task_id, action)
        )

    def restart_task(self) -> None:
        task_id = self._selected_task_id()
        if task_id:
            self._async_action("重启任务", lambda: self.service.restart_task(task_id))

    def delete_task(self) -> None:
        task_id = self._selected_task_id()
        if not task_id:
            return
        answer = messagebox.askyesnocancel(
            "删除任务",
            "选择“是”会同时删除该任务的日志和运行状态；选择“否”只删除任务 YAML。",
            parent=self.root,
        )
        if answer is None:
            return
        try:
            self.service.delete_task(task_id, purge_runtime=answer)
            self.refresh_all()
        except Exception as exc:
            messagebox.showerror("删除失败", str(exc), parent=self.root)

    def stop_process(self) -> None:
        selected = self.process_tree.selection()
        if not selected:
            return
        values = self.process_tree.item(selected[0], "values")
        pid = int(values[2])
        if not messagebox.askyesno(
            "确认终止", f"确认终止受控进程 PID {pid}？", parent=self.root
        ):
            return
        self._async_action("终止进程", lambda: self.service.stop_process(pid))

    def refresh_all(self, select: str | None = None) -> None:
        try:
            items = self.service.list_tasks()
        except Exception as exc:
            self.status_value.set(f"刷新失败：{exc}")
            return
        old_selection = select or self._selected_task_id()
        self.task_tree.delete(*self.task_tree.get_children())
        task_ids: list[str] = []
        for item in items:
            task = item["task"]
            state = item["state"]
            task_id = task["id"]
            task_ids.append(task_id)
            tag = (
                state["status"]
                if state["status"] in {"failed", "running", "finishing"}
                else ""
            )
            self.task_tree.insert(
                "",
                tk.END,
                iid=task_id,
                values=(
                    task_id,
                    task.get("name", ""),
                    task.get("preset", ""),
                    state.get("status", ""),
                    state.get("phase", ""),
                    state.get("runner_pid") or "",
                    state.get("started_at") or "",
                ),
                tags=(tag,) if tag else (),
            )
        if old_selection and self.task_tree.exists(old_selection):
            self.task_tree.selection_set(old_selection)
            self.task_tree.see(old_selection)
        self.log_task_box.configure(values=task_ids)
        if self.log_task_value.get() not in task_ids:
            self.log_task_value.set(task_ids[0] if task_ids else "")
        self.refresh_processes()
        self.status_value.set(f"已刷新，共 {len(items)} 个任务")

    def refresh_processes(self) -> None:
        try:
            processes = self.service.list_processes()
        except Exception as exc:
            self.status_value.set(f"进程刷新失败：{exc}")
            return
        self.process_tree.delete(*self.process_tree.get_children())
        for index, process in enumerate(processes):
            self.process_tree.insert(
                "",
                tk.END,
                iid=f"process-{index}-{process['pid']}",
                values=(
                    process["task_id"],
                    process["role"],
                    process["pid"],
                    process["status"],
                    process.get("started_at") or "",
                    process.get("command") or "",
                ),
            )

    def reload_config(self, kind: str) -> None:
        try:
            self.service.reload()
            content = self.service.config_manager.read_text(kind)
        except Exception as exc:
            messagebox.showerror("读取配置失败", str(exc), parent=self.root)
            return
        editor = self.config_editors.get(kind)
        if editor is None:
            return
        editor.delete("1.0", tk.END)
        editor.insert("1.0", content)
        editor.edit_modified(False)

    def save_config(self, kind: str) -> None:
        editor = self.config_editors[kind]
        try:
            self.service.config_manager.save_text(kind, editor.get("1.0", "end-1c"))
            self.service.reload()
        except Exception as exc:
            messagebox.showerror("配置保存失败", str(exc), parent=self.root)
            return
        editor.edit_modified(False)
        self.refresh_all()
        messagebox.showinfo(
            "配置已保存", "YAML 已通过校验并写入磁盘。", parent=self.root
        )

    def open_config_location(self, kind: str) -> None:
        path = (
            self.service.paths.config_file
            if kind == "project"
            else self.service.paths.webhook_file
        )
        self._open_path(path.parent)

    def open_log_location(self) -> None:
        task_id = self.log_task_value.get()
        path = (
            self.service.store.log_path(task_id).parent
            if task_id
            else self.service.store.task_runtime_dir
        )
        path.mkdir(parents=True, exist_ok=True)
        self._open_path(path)

    @staticmethod
    def _open_path(path: Path) -> None:
        try:
            if os.name == "nt":
                os.startfile(path)  # type: ignore[attr-defined]
            elif sys.platform == "darwin":
                subprocess.Popen(["open", str(path)])
            else:
                subprocess.Popen(["xdg-open", str(path)])
        except OSError as exc:
            messagebox.showerror("无法打开路径", str(exc))

    def refresh_log(self) -> None:
        task_id = self.log_task_value.get()
        if not task_id:
            return
        path = self.service.store.log_path(task_id)
        try:
            if path.exists():
                size = path.stat().st_size
                with path.open("rb") as handle:
                    handle.seek(max(0, size - 250_000))
                    content = handle.read().decode("utf-8", errors="replace")
            else:
                content = "日志尚未生成。\n"
        except OSError as exc:
            content = f"读取日志失败：{exc}\n"
        self.log_text.configure(state=tk.NORMAL)
        self.log_text.delete("1.0", tk.END)
        self.log_text.insert("1.0", content)
        self.log_text.see(tk.END)
        self.log_text.configure(state=tk.DISABLED)

    def _tab_changed(self) -> None:
        if self.notebook.index(self.notebook.select()) == 3:
            self.refresh_log()

    def _async_action(self, label: str, operation: Callable[[], object]) -> None:
        if self._busy:
            self.status_value.set("已有管理操作正在执行，请稍候。")
            return
        self._busy += 1
        self.status_value.set(f"{label}中……")

        def work() -> None:
            try:
                operation()
            except Exception as exc:
                self.root.after(
                    0, lambda error=exc: self._action_finished(label, error)
                )
            else:
                self.root.after(0, lambda: self._action_finished(label, None))

        threading.Thread(target=work, name=f"gui-{label}", daemon=True).start()

    def _action_finished(self, label: str, error: Exception | None) -> None:
        self._busy = max(0, self._busy - 1)
        if error:
            messagebox.showerror(f"{label}失败", str(error), parent=self.root)
        self.refresh_all()
        self.status_value.set(f"{label}{'失败' if error else '完成'}")

    def _periodic_refresh(self) -> None:
        if self._closed:
            return
        if self._busy == 0:
            self.refresh_all()
            if self.notebook.index(self.notebook.select()) == 3:
                self.refresh_log()
        self.root.after(self.REFRESH_MS, self._periodic_refresh)

    def close(self) -> None:
        self._closed = True
        self.root.destroy()


def launch_gui(root_path: Path | None = None) -> None:
    root = tk.Tk()
    service = ManagerService(root_path)
    TimelapseApp(root, service)
    root.mainloop()
