#!/usr/bin/env python3
# usage: bench.py FILTER RUNS  -> min / median of per-run medians per case
import subprocess, re, sys, os, collections, statistics
flt, runs = sys.argv[1], int(sys.argv[2])
res = collections.defaultdict(list)
units = {'ns': 1e-3, 'us': 1, 'ms': 1e3, 's': 1e6, 'B': 1 / 1024, 'Bytes': 1 / 1024, 'KiB': 1, 'MiB': 1024}
for i in range(runs):
    out = subprocess.run(['cjpm', 'bench', f'--filter={flt}'], capture_output=True, text=True,
                         env={**os.environ, 'cjHeapSize': '4GB'}).stdout
    out = re.sub(r'\x1b\[[0-9;]*[A-Za-z]|\x1b[78]', '', out)
    cls = None
    for line in out.splitlines():
        m = re.search(r'TCS: (\w+)', line)
        if m:
            cls = m.group(1)
            continue
        m = re.match(r'\s*\|\s*(\w+)\s*\|\s*([\d.E+-]+) (\w+)\s*\|', line)
        if m and cls and m.group(1) != 'Case':
            res[f'{cls}.{m.group(1)}'].append(float(m.group(2)) * units[m.group(3)])
for k, v in res.items():
    u = 'KiB' if 'Allocation' in k else 'us'
    print(f'{k:55s} min {min(v):10.3f} {u}  med {statistics.median(v):10.3f}  runs {["%.3f" % x for x in v]}')
