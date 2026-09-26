"""Arbitrary local voice filenames can be installed without editing source."""

from pathlib import Path
import subprocess
import sys
import tempfile


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "install_local_audio.py"
with tempfile.TemporaryDirectory() as scratch:
    root = Path(scratch)
    source = root / "source"
    target = root / "target"
    source.mkdir()
    (source / "custom_rank_voice.wav").write_bytes(b"test fixture")
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--source-dir", str(source),
         "--target-dir", str(target), "--file", "custom_rank_voice.wav"],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, result.stderr
    assert (target / "custom_rank_voice.wav").read_bytes() == b"test fixture"
    assert not (target / "unrelated.mp3").exists()
    assert not (target / "impact.wav").exists()

print("Arbitrary local sound installation: PASS")
