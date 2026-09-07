"""Cross-platform process/OS resource sampling.

Gauges are populated by :func:`refresh_resource_gauges`, which is called:

* lazily on every ``GET /metrics`` scrape (cheap, cached), and
* on a fixed cadence by the background sampler task so long time-series
  exist even when nothing scrapes for a while.

Sampling strategy (no hard dependency):

1. ``psutil`` when importable (typical dev boxes / monitoring hosts)
2. Linux ``/proc/self`` fallback (runtime container — no psutil installed)
3. stdlib-only baseline (threads, start time) everywhere

An unsuccessful probe never raises: the affected gauges simply keep their
previous value and the collector moves on.
"""

from __future__ import annotations

import os
import threading
import time
from typing import Dict, Optional

from app.core.observability import metrics
from app.core.logging import get_logger

logger = get_logger("app.observability.resource")

PROCESS_START_TIME: float = time.time()


def collect_snapshot() -> Dict[str, Optional[float]]:
    """Return a numeric snapshot ~{key: value} for the live process/OS."""
    snap: Dict[str, Optional[float]] = {
        "rss_bytes": None,
        "vms_bytes": None,
        "cpu_seconds": None,
        "threads": float(threading.active_count()),
        "open_fds": None,
        "start_time": PROCESS_START_TIME,
        "load_1": None,
        "load_5": None,
        "load_15": None,
    }

    # 1) psutil, when available.
    try:
        import psutil  # type: ignore

        proc = psutil.Process()
        mem = proc.memory_info()
        snap["rss_bytes"] = float(mem.rss)
        snap["vms_bytes"] = float(mem.vms)
        cpu = proc.cpu_times()
        snap["cpu_seconds"] = float(cpu.user + cpu.system)
        snap["threads"] = float(proc.num_threads())
        conn = getattr(proc, "num_fds", None)
        snap["open_fds"] = float(conn()) if conn else None
        snap["start_time"] = float(proc.create_time())
        loads = os.getloadavg() if hasattr(os, "getloadavg") else None
        if loads:
            snap["load_1"], snap["load_5"], snap["load_15"] = (float(x) for x in loads)
        return snap
    except Exception as exc:  # noqa: BLE001 — fall through to /proc
        logger.debug("psutil resource sampling unavailable: %s", exc)

    # 2) Linux /proc/self fallback (works inside the runtime container).
    try:
        status: Dict[str, str] = {}
        with open("/proc/self/status", encoding="utf-8") as fh:  # noqa: PTH123
            for line in fh:
                key, _, value = line.partition(":")
                status[key.strip()] = value.strip()
        vms = status.get("VmSize", "")
        rss = status.get("VmRSS", "")
        if rss and rss.endswith("kB"):
            snap["rss_bytes"] = float(rss[:-2]) * 1024.0
        if vms and vms.endswith("kB"):
            snap["vms_bytes"] = float(vms[:-2]) * 1024.0
        threads = status.get("Threads")
        if threads:
            snap["threads"] = float(threads)
        try:
            snap["open_fds"] = float(len(os.listdir("/proc/self/fd")))  # noqa: PTH112
        except OSError:
            snap["open_fds"] = None
        snap["start_time"] = PROCESS_START_TIME
        loads = os.getloadavg() if hasattr(os, "getloadavg") else None
        if loads:
            snap["load_1"], snap["load_5"], snap["load_15"] = (float(x) for x in loads)
    except Exception as exc:  # noqa: BLE001 — /proc missing on dev boxes
        logger.debug("Linux /proc resource sampling unavailable: %s", exc)

    return snap


def refresh_resource_gauges() -> Dict[str, Optional[float]]:
    """Sample the process/OS and write every gauge (best-effort, never raises)."""
    snap = collect_snapshot()
    try:
        if snap["rss_bytes"] is not None:
            metrics.process_rss_bytes.set(snap["rss_bytes"])
        if snap["vms_bytes"] is not None:
            metrics.process_virtual_memory_bytes.set(snap["vms_bytes"])
        if snap["cpu_seconds"] is not None:
            metrics.process_cpu_seconds_total.set(snap["cpu_seconds"])
        if snap["threads"] is not None:
            metrics.process_threads.set(snap["threads"])
        if snap["open_fds"] is not None:
            metrics.process_open_fds.set(snap["open_fds"])
        if snap["start_time"] is not None:
            metrics.process_start_time_seconds.set(snap["start_time"])
        for name, load_gauge in (
            ("load_1", metrics.system_load_1),
            ("load_5", metrics.system_load_5),
            ("load_15", metrics.system_load_15),
        ):
            if snap[name] is not None:
                load_gauge.set(snap[name])
    except Exception as exc:  # noqa: BLE001
        logger.warning("Failed to refresh resource gauges: %s", exc)
    return snap