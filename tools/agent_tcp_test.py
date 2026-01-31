import argparse
import json
import queue
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path


DEFAULT_GODOT = r"C:\Users\olive\Apps\Godot_v4.5.1-stable_win64.exe"
PORT_LINE_PREFIX = "AGENT_TCP_PORT="


class LineClient:
    def __init__(self, sock: socket.socket):
        self._sock = sock
        self._buffer = b""

    def send_json(self, payload: dict) -> None:
        data = json.dumps(payload, separators=(",", ":"), ensure_ascii=True).encode("utf-8") + b"\n"
        self._sock.sendall(data)

    def recv_json(self, timeout: float) -> dict:
        self._sock.settimeout(timeout)
        while b"\n" not in self._buffer:
            chunk = self._sock.recv(4096)
            if not chunk:
                raise RuntimeError("Connection closed by server.")
            self._buffer += chunk
        line, self._buffer = self._buffer.split(b"\n", 1)
        text = line.decode("utf-8").strip()
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError as exc:
            raise RuntimeError(f"Invalid JSON response: {text}") from exc
        if not isinstance(parsed, dict):
            raise RuntimeError(f"Expected JSON object response, got: {text}")
        return parsed


def _read_output_lines(stream, sink: queue.Queue) -> None:
    for line in stream:
        sink.put(line)


def _collect_test_files(paths: list[Path]) -> list[Path]:
    collected: list[Path] = []
    for path in paths:
        if path.is_dir():
            collected.extend(sorted(path.glob("*.json")))
        elif path.is_file():
            collected.append(path)
        else:
            raise FileNotFoundError(f"Test path not found: {path}")
    return collected


def _load_steps(path: Path) -> list[dict]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if isinstance(data, list):
        steps = data
    elif isinstance(data, dict) and isinstance(data.get("steps"), list):
        steps = data["steps"]
    else:
        raise ValueError(f"Test file {path} must be a JSON array or {{\"steps\": [...]}}.")
    for index, step in enumerate(steps):
        if not isinstance(step, dict):
            raise ValueError(f"Step {index + 1} in {path} must be a JSON object.")
    return steps


def _load_tests(paths: list[Path]) -> list[tuple[Path, list[dict]]]:
    test_files = _collect_test_files(paths)
    tests: list[tuple[Path, list[dict]]] = []
    for path in test_files:
        tests.append((path, _load_steps(path)))
    return tests


def _has_screenshot(tests: list[tuple[Path, list[dict]]]) -> bool:
    for _, steps in tests:
        for step in steps:
            if step.get("type") == "command" and step.get("name") == "screenshot":
                return True
    return False


def _start_godot(godot_path: Path, project_path: Path, headless: bool, port: int | None) -> tuple[subprocess.Popen, queue.Queue, threading.Thread]:
    cmd = [str(godot_path), "--path", str(project_path)]
    if headless:
        cmd.append("--headless")
    cmd.append("--")
    if port is None:
        cmd.append("--agent-tcp")
    else:
        cmd.extend(["--agent-tcp-port", str(port)])
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    if proc.stdout is None:
        raise RuntimeError("Failed to capture Godot stdout.")
    output_queue: queue.Queue = queue.Queue()
    thread = threading.Thread(target=_read_output_lines, args=(proc.stdout, output_queue), daemon=True)
    thread.start()
    return proc, output_queue, thread


def _wait_for_port(proc: subprocess.Popen, output_queue: queue.Queue, timeout: float) -> int:
    deadline = time.monotonic() + timeout
    buffered: list[str] = []
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            break
        try:
            line = output_queue.get(timeout=0.1)
        except queue.Empty:
            continue
        buffered.append(line.rstrip())
        if PORT_LINE_PREFIX in line:
            value = line.strip().split(PORT_LINE_PREFIX, 1)[-1]
            try:
                return int(value)
            except ValueError:
                break
    joined = "\n".join(buffered[-25:])
    raise RuntimeError(f"Timed out waiting for {PORT_LINE_PREFIX} in Godot output.\nRecent output:\n{joined}")


def _run_tests(client: LineClient, tests: list[tuple[Path, list[dict]]], response_timeout: float, verbose: bool) -> int:
    failures = 0
    for path, steps in tests:
        label = path.stem
        for index, step in enumerate(steps):
            payload = dict(step)
            payload.setdefault("id", f"{label}:{index + 1}")
            if "type" not in payload:
                raise ValueError(f"Missing 'type' in {path} step {index + 1}.")
            client.send_json(payload)
            response = client.recv_json(response_timeout)
            if verbose:
                print(f"{label}:{index + 1} -> {response}")
            if response.get("id") != payload["id"]:
                print(f"Warning: response id mismatch for {label}:{index + 1}: {response.get('id')}")
            if not response.get("ok", False):
                failures += 1
                print(f"FAIL {label}:{index + 1}: {json.dumps(response, ensure_ascii=True)}")
                return failures
        print(f"PASS {path}")
    return failures


def _shutdown(proc: subprocess.Popen, client: LineClient | None, response_timeout: float) -> None:
    if client is not None:
        try:
            client.send_json({"type": "command", "name": "quit", "id": "shutdown"})
            client.recv_json(response_timeout)
        except Exception:
            pass
    try:
        proc.wait(timeout=5)
        return
    except subprocess.TimeoutExpired:
        proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()


def main() -> int:
    parser = argparse.ArgumentParser(description="Run agent TCP JSON tests against the Godot project.")
    parser.add_argument("paths", nargs="+", help="JSON test files or directories containing JSON tests.")
    parser.add_argument("--godot", default=DEFAULT_GODOT, help="Path to Godot executable.")
    parser.add_argument("--project", default=None, help="Path to project root (defaults to repo root).")
    parser.add_argument("--port", type=int, default=None, help="Fixed port for the agent TCP server.")
    parser.add_argument("--no-headless", action="store_true", help="Run Godot with a visible window.")
    parser.add_argument("--startup-timeout", type=float, default=10.0, help="Seconds to wait for the TCP port.")
    parser.add_argument("--response-timeout", type=float, default=5.0, help="Seconds to wait for each response.")
    parser.add_argument("--verbose", action="store_true", help="Print all responses.")
    args = parser.parse_args()

    godot_path = Path(args.godot)
    if not godot_path.exists():
        print(f"Godot executable not found: {godot_path}")
        return 2

    if args.project:
        project_path = Path(args.project)
    else:
        project_path = Path(__file__).resolve().parents[1]
    if not project_path.exists():
        print(f"Project path not found: {project_path}")
        return 2

    tests = _load_tests([Path(p) for p in args.paths])
    if not tests:
        print("No JSON test files found.")
        return 2

    proc = None
    client = None
    try:
        headless = not args.no_headless
        if headless and _has_screenshot(tests):
            print("Detected screenshot command; running with a visible window.")
            headless = False
        proc, output_queue, _ = _start_godot(
            godot_path=godot_path,
            project_path=project_path,
            headless=headless,
            port=args.port,
        )
        port = args.port
        if port is None:
            port = _wait_for_port(proc, output_queue, args.startup_timeout)
        sock = socket.create_connection(("127.0.0.1", port), timeout=5)
        client = LineClient(sock)
        failures = _run_tests(client, tests, args.response_timeout, args.verbose)
        return 1 if failures else 0
    except Exception as exc:
        print(f"Error: {exc}")
        return 1
    finally:
        if proc is not None:
            _shutdown(proc, client, args.response_timeout)


if __name__ == "__main__":
    raise SystemExit(main())
