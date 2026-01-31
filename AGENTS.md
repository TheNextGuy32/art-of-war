## Agent TCP test requirement

All changes made by agents **must** be tested by starting the Godot project with the agent TCP server enabled, then running JSON test files against it.

### Required command

Use the Godot executable at:

`C:\Users\olive\Apps\Godot_v4.5.1-stable_win64.exe`

Run tests with the helper script:

```bash
python tools/agent_tcp_test.py tests/agent
```

This script starts Godot with the required parameter and connects to the local TCP server.
If any test uses the `screenshot` command, the runner will automatically disable headless mode.

### Agent TCP parameter

The TCP server is only started when one of the following parameters is passed to Godot:

- `--agent-tcp` (auto-selects a free port and prints `AGENT_TCP_PORT=NNNNN`)
- `--agent-tcp-port 60111` (uses a fixed port)

Godot should be launched with `--` before the agent args, for example:

```bash
C:\Users\olive\Apps\Godot_v4.5.1-stable_win64.exe --path . --headless -- --agent-tcp
```

### Test file format

Tests are local JSON files under `tests/agent/` with descriptive names.
Each file is a JSON array of line-delimited messages, sent in order:

- `{"type":"command","name":"ping"}`
- `{"type":"command","name":"set","key":"score","value":42}`
- `{"type":"assert","op":"equals","key":"score","expected":42}`

Supported assert ops: `equals`, `exists`, `truthy`, `contains`.

The server responds with JSON objects containing `ok: true/false`. The test runner fails on the first `ok: false`.

### Movement + screenshot commands

The agent TCP server accepts these command names (all `type:"command"`):

- `walk_to` with `position:[x,y,z]` or `x`/`y`/`z`
- `look_at` with `target:"object_id"` or `position:[x,y,z]`
- `screenshot` with `filename:"bug.png"` and `description:"One sentence about the issue."`

Screenshots are saved under `res://tmp/`. For every screenshot `bug.png`, the server also writes a sibling file
`bug_description.png` containing the provided one-sentence description. The response includes absolute paths:
`path` and `description_path` so the agent can confirm creation.
