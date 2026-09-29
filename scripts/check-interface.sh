#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/SiliconPulse.app/Contents/MacOS/SiliconPulse"
if pgrep -x SiliconPulse >/dev/null; then
    echo 'Quit SiliconPulse before running interface verification.' >&2
    exit 1
fi
OUTPUT="$(mktemp -d /tmp/SiliconPulse-Interface.XXXXXX)"
"$BIN" "--ui-snapshot=$OUTPUT" > "$OUTPUT/render.log" 2>&1
python3 - "$OUTPUT" <<'PY'
import pathlib, struct, sys
root = pathlib.Path(sys.argv[1])
expected = {'dashboard': (420,820), 'dashboard-wide': (760,900), 'performance': (760,900), 'edit': (420,660)}
expected.update({f'settings-{tab}': (860,680) for tab in range(7)})
for name, (width,height) in expected.items():
    for mode in ('light','dark'):
        path=root/f'{name}-{mode}.png'
        data=path.read_bytes()
        assert data[:8]==b'\x89PNG\r\n\x1a\n', path
        actual=struct.unpack('>II',data[16:24])
        assert actual in [(width,height),(width*2,height*2)], (path,actual)
data=(root/'minimum-panel.png').read_bytes()
assert struct.unpack('>II',data[16:24]) in [(340,420),(680,840)]
log=(root/'render.log').read_text()
assert 'UI_RENDER_OK' in log,log
assert 'Unable to simultaneously satisfy constraints' not in log,log
print('PASS: 23 native view renders; correct dimensions; no conflicting Auto Layout constraints.')
print(f'Inspect screenshots: {root}')
PY
