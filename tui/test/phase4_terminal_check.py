"""Run real 120x36 MOCK terminals; retain decoded text only, never ANSI captures."""
import codecs
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import signal
import struct
import termios
import time
import unicodedata

ROOT = Path("/Users/vishalnaveen/Downloads/tickweave-tui")
PREFIX = "cd /Users/vishalnaveen/Downloads/tickweave-tui && eval $(opam env --switch 5.2.0+ox) && "


class Screen:
    def __init__(self, width=120, height=36):
        self.width, self.height = width, height
        self.cells = [[" "] * width for _ in range(height)]
        self.x = self.y = 0
        self.escape = ""
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")

    def feed(self, data):
        for char in self.decoder.decode(data):
            if self.escape:
                self.escape += char
                if self.escape == "\x1b[":
                    continue
                if self.escape.startswith("\x1b["):
                    if "@" <= char <= "~":
                        self.csi(self.escape[2:-1], char)
                        self.escape = ""
                elif len(self.escape) >= 2:
                    self.escape = ""
                continue
            if char == "\x1b":
                self.escape = char
            elif char == "\r":
                self.x = 0
            elif char == "\n":
                self.y = min(self.height - 1, self.y + 1)
            elif char == "\b":
                self.x = max(0, self.x - 1)
            elif ord(char) >= 32:
                size = 0 if unicodedata.combining(char) else (2 if unicodedata.east_asian_width(char) in "WF" else 1)
                if size and self.x < self.width:
                    self.cells[self.y][self.x] = char
                    if size == 2 and self.x + 1 < self.width:
                        self.cells[self.y][self.x + 1] = ""
                elif not size and self.x:
                    self.cells[self.y][self.x - 1] += char
                self.x = min(self.width, self.x + size)

    def csi(self, raw, final):
        if raw.startswith("?"):
            return
        try:
            values = [int(part or "0") for part in raw.split(";")]
        except ValueError:
            return
        n = (values[0] or 1) if values else 1
        if final in "Hf":
            self.y = min(self.height - 1, max(0, n - 1))
            self.x = min(self.width - 1, max(0, ((values[1] or 1) if len(values) > 1 else 1) - 1))
        elif final == "A":
            self.y = max(0, self.y - n)
        elif final == "B":
            self.y = min(self.height - 1, self.y + n)
        elif final == "C":
            self.x = min(self.width, self.x + n)
        elif final == "D":
            self.x = max(0, self.x - n)
        elif final in "EF":
            self.y = max(0, min(self.height - 1, self.y + (n if final == "E" else -n)))
            self.x = 0
        elif final == "G":
            self.x = max(0, min(self.width - 1, n - 1))
        elif final == "J":
            if values[0] in (2, 3):
                self.cells = [[" "] * self.width for _ in range(self.height)]
            elif values[0] == 0:
                self.cells[self.y][self.x:] = [" "] * (self.width - self.x)
                for row in range(self.y + 1, self.height):
                    self.cells[row] = [" "] * self.width
        elif final == "K":
            if values[0] == 2:
                self.cells[self.y] = [" "] * self.width
            elif values[0] == 0:
                self.cells[self.y][self.x:] = [" "] * (self.width - self.x)

    def text(self):
        return "\n".join("".join(row).rstrip() for row in self.cells) + "\n"


def stop_child(pid):
    # pty.fork creates a new session/process group owned by this child.
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pid, sig)
        except PermissionError:
            # Some macOS execution policies prohibit process-group signals.
            os.kill(pid, sig)
        except ProcessLookupError:
            pass
        until = time.monotonic() + 2
        while time.monotonic() < until:
            done, status = os.waitpid(pid, os.WNOHANG)
            if done:
                return status
            time.sleep(0.05)
    raise RuntimeError(f"PTY child {pid} failed to exit after SIGKILL")


def run(scenario):
    command = PREFIX + "stty rows 36 columns 120 && env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor ./_build/default/tui/bin/main.exe console --mode mock --scenario " + scenario
    pid, fd = pty.fork()
    if pid == 0:
        os.execl("/bin/zsh", "zsh", "-c", command)
    screen = Screen()
    started = None
    deadline = time.monotonic() + 60
    actions = [(1.0, b"c"), (2.0, b"A"), (2.2, b"apply"), (2.5, b"\r")]
    captures = [(4.2, "applying"), (6.5, "result")]
    if scenario == "update_ok":
        actions += [(8.0, b"\x1b"), (8.5, b"3Gk\r")]
        captures += [(11.5, "inspector")]
    else:
        captures += [(11.5, "unknown")]
    actions += [(12.0, b"\x1b"), (12.5, b"q")]
    saved = {}
    status = None
    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 36, 120, 0, 0))
        while time.monotonic() < deadline:
            ready, _, _ = select.select([fd], [], [], 0.05)
            if ready:
                try:
                    data = os.read(fd, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
                if not data:
                    break
                screen.feed(data)
                if started is None and "tickweave" in screen.text():
                    started = time.monotonic()
            if started is not None:
                elapsed = time.monotonic() - started
                while actions and elapsed >= actions[0][0]:
                    _, keys = actions.pop(0)
                    os.write(fd, keys)
                while captures and elapsed >= captures[0][0]:
                    _, name = captures.pop(0)
                    saved[name] = screen.text()
        done, exit_status = os.waitpid(pid, os.WNOHANG)
        status = exit_status if done else stop_child(pid)
        duration = 0 if started is None else time.monotonic() - started
    finally:
        os.close(fd)
        if status is None:
            try:
                stop_child(pid)
            except (ProcessLookupError, ChildProcessError):
                pass
    if started is None or duration < 10 or os.waitstatus_to_exitcode(status) != 0:
        raise RuntimeError(f"{scenario}: terminal failed, duration={duration:.2f}, status={status}; screen={screen.text()}")
    for name, content in saved.items():
        (ROOT / "tui/test" / f"phase4-terminal-{scenario}-{name}.txt").write_text(content)
    result = saved["result"]
    assert "Configuration review" in result
    applying_header = saved["applying"].splitlines()[0]
    assert "ACK v12" in applying_header and "APPLYING" in applying_header
    assert "v13" not in applying_header
    if scenario == "update_ok":
        assert "ACK v13" in result.splitlines()[0]
        assert "cfg v13" in saved["inspector"] and "MOCK FROZEN" in saved["inspector"]
    else:
        for unknown in (result, saved["unknown"]):
            assert "STATE UNKNOWN" in unknown and "last ack v12" in unknown
            assert "UNKNOWN" in unknown.splitlines()[0] and "v12" in unknown.splitlines()[0]
            assert "v13" not in unknown and "disabled" not in unknown.lower()
    summary = {"scenario": scenario, "size": "120x36", "duration_s": round(duration, 2),
               "exit_code": os.waitstatus_to_exitcode(status), "command": command,
               "header": result.splitlines()[0], "captures": list(saved)}
    print(json.dumps(summary, ensure_ascii=False), flush=True)
    return summary


if __name__ == "__main__":
    results = [run("update_ok"), run("lost_at_activate")]
    (ROOT / "tui/test/phase4-terminal-results.json").write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n")
