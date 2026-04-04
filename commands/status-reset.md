---
name: baton:status-reset
description: Reset pipeline status to idle. Clears state.json and statusline cache only — artifacts (plan.md, todo.md, etc.) are preserved.
---

# /baton:status-reset

Reset the pipeline state to idle without touching any artifacts.

## Steps

### Step 1. Re-initialize state.json
Resolve plugin path from `installed_plugins.json`, then call `state_init()` (single source of truth):

```bash
python3 -c "
import json, os, re

# 1. Resolve plugin root from installed_plugins.json
ip = os.path.expanduser('~/.claude/plugins/installed_plugins.json')
with open(ip) as f: data = json.load(f)
plugin_root = None
for key, entries in data.get('plugins', {}).items():
    if 'claude-baton' in key:
        for e in (entries if isinstance(entries, list) else [entries]):
            if isinstance(e, dict) and e.get('installPath'):
                plugin_root = e['installPath']; break
        if plugin_root: break
assert plugin_root, 'claude-baton plugin not found'

# 2. Extract state schema from state_init() in state-manager.sh (single source of truth)
sm = os.path.join(plugin_root, 'hooks', 'scripts', 'state-manager.sh')
with open(sm) as f: src = f.read()
m = re.search(r'state\s*=\s*(\{.*?\})\s*\nos\.makedirs', src, re.DOTALL)
assert m, 'Could not extract state schema from state-manager.sh'
state = eval(m.group(1))  # safe: only from our own plugin file

# 3. Validate extracted schema
assert isinstance(state, dict), f'Schema is not a dict: {type(state)}'
required = ['version', 'currentPhase', 'phaseFlags', 'reviewTracker', 'workerTracker', 'reworkStatus']
missing = [k for k in required if k not in state]
assert not missing, f'Schema missing required keys: {missing}'
assert isinstance(state['phaseFlags'], dict), 'phaseFlags must be dict'
assert isinstance(state['reviewTracker'], dict), 'reviewTracker must be dict'

# 4. Write state.json
sf = os.path.join('.baton', 'state.json')
os.makedirs('.baton', exist_ok=True)
with open(sf, 'w') as f: json.dump(state, f, indent=2); f.write('\n')
print('state.json reset to idle (schema from state-manager.sh)')
"
```

### Step 2. Clear statusline cache
```bash
rm -f .baton/logs/.last-prompt-phase
```

Note: `.agent-stack` is sealed by main-guard-bash — do NOT delete via Bash.
It resets naturally when a new pipeline starts.

## Confirmation

Output exactly:

```
Pipeline status reset to idle.
  State: idle | Tier: — | Artifacts: preserved
```
