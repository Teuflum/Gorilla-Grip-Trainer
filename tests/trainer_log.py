"""Shared precondition for the in-game tests, which read Trainer event lines."""

from pathlib import Path


LOG = Path.home() / "OpenplanetNext" / "Openplanet.log"
LOADED = "Loaded plugin 'GorillaGripTrainer'"
MARKER = "Gorilla Grip Trainer event logging "


def event_logging_enabled(log_text: str) -> bool:
    """True when the latest marker since the latest plugin load says "on"."""
    since_load = log_text.rsplit(LOADED, 1)
    if len(since_load) < 2:
        return False
    state = None
    for line in since_load[1].splitlines():
        if MARKER in line:
            state = line.split(MARKER, 1)[1].strip()
    return state == "on"


def require_event_logging(log_path: Path = LOG) -> None:
    text = log_path.read_text(encoding="utf-8", errors="replace")
    if not event_logging_enabled(text):
        raise SystemExit(
            "Trainer event logging is off. In Openplanet developer mode, enable Settings → "
            "Gorilla Grip Trainer → Debug → Log trainer events, then rerun.")
