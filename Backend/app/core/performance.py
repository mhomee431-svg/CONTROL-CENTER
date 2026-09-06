"""Performance benchmarking and target tracking.

Defines measurable performance targets:
- API p95 latency: < 300ms
- Simple DB query: < 100ms
- Search query: < 500ms
- Nearby search: < 300ms
- Barcode lookup: < 100ms
"""
import logging
import time
from functools import wraps
from typing import Any, Callable, Optional

from app.core.config import settings

logger = logging.getLogger("app.core.performance")


# Performance targets in milliseconds
TARGETS = {
    "api_p95_ms": 300,
    "api_p99_ms": 500,
    "db_simple_query_ms": 100,
    "search_query_ms": 500,
    "nearby_search_ms": 300,
    "barcode_lookup_ms": 100,
}


class PerformanceTracker:
    """Track and report performance metrics."""
    
    def __init__(self):
        self._measurements: dict[str, list[float]] = {}
    
    def record(self, metric: str, value_ms: float) -> None:
        """Record a latency measurement."""
        if metric not in self._measurements:
            self._measurements[metric] = []
        self._measurements[metric].append(value_ms)
    
    def percentile(self, metric: str, p: float) -> Optional[float]:
        """Get percentile value for a metric."""
        values = self._measurements.get(metric, [])
        if not values:
            return None
        sorted_values = sorted(values)
        idx = int(len(sorted_values) * p / 100)
        return sorted_values[min(idx, len(sorted_values) - 1)]
    
    def average(self, metric: str) -> Optional[float]:
        """Get average value for a metric."""
        values = self._measurements.get(metric, [])
        if not values:
            return None
        return sum(values) / len(values)
    
    def get_report(self) -> dict[str, Any]:
        """Generate performance report."""
        report = {"targets": TARGETS, "metrics": {}, "compliance": {}}
        
        for metric in TARGETS:
            p95 = self.percentile(metric, 95)
            avg = self.average(metric)
            target = TARGETS[metric]
            
            report["metrics"][metric] = {
                "p95_ms": p95,
                "average_ms": avg,
                "target_ms": target,
                "samples": len(self._measurements.get(metric, [])),
            }
            
            if p95 is not None:
                report["compliance"][metric] = p95 <= target
        
        return report


tracker = PerformanceTracker()


class benchmark:
    """Context manager for benchmarking code blocks."""
    
    def __init__(self, metric: str):
        self.metric = metric
        self.start_time = 0
    
    def __enter__(self):
        self.start_time = time.perf_counter()
        return self
    
    def __exit__(self, *args):
        elapsed_ms = (time.perf_counter() - self.start_time) * 1000
        tracker.record(self.metric, elapsed_ms)
        
        target = TARGETS.get(self.metric)
        if target and elapsed_ms > target:
            logger.warning("Performance target missed: %s took %.2fms (target: %dms)", self.metric, elapsed_ms, target)


def track_latency(metric: str) -> Callable:
    """Decorator to track function latency."""
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs):
            start = time.perf_counter()
            try:
                return func(*args, **kwargs)
            finally:
                elapsed_ms = (time.perf_counter() - start) * 1000
                tracker.record(metric, elapsed_ms)
        return wrapper
    return decorator


def get_performance_report() -> dict[str, Any]:
    """Get current performance report."""
    return tracker.get_report()


def check_latency_target(metric: str, latency_ms: float) -> bool:
    """Check if a latency measurement meets the target."""
    target = TARGETS.get(metric)
    if target is None:
        return True
    return latency_ms <= target