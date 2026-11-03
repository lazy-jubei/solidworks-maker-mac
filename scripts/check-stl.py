#!/usr/bin/env python3
"""Validate the binary millimetre STL of the dedicated 50x30x25 mm cut box.

This is a specific regression fixture check, not a general printability checker.
"""
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import struct
import sys


def check(path):
    data = path.read_bytes()
    if len(data) < 84:
        raise ValueError('Truncated binary STL')
    count = struct.unpack_from('<I', data, 80)[0]
    if count == 0 or len(data) != 84 + 50 * count:
        raise ValueError('Invalid binary STL triangle count/length')
    edges = Counter()
    directed = Counter()
    neighbours = defaultdict(set)
    vertices = set()
    volume = 0.0
    for offset in range(84, len(data), 50):
        row = struct.unpack_from('<12fH', data, offset)
        if not all(math.isfinite(v) for v in row[:12]):
            raise ValueError('Non-finite mesh coordinate/normal')
        a, b, c = (tuple(row[start:start + 3]) for start in (3, 6, 9))
        u, v = tuple(b[i] - a[i] for i in range(3)), tuple(c[i] - a[i] for i in range(3))
        cross = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
        if sum(x*x for x in cross) < 1e-20:
            raise ValueError('Degenerate triangle')
        volume += (a[0]*(b[1]*c[2]-b[2]*c[1]) + a[1]*(b[2]*c[0]-b[0]*c[2]) + a[2]*(b[0]*c[1]-b[1]*c[0])) / 6
        vertices.update((a, b, c))
        for p, q in ((a, b), (b, c), (c, a)):
            edges[tuple(sorted((p, q)))] += 1
            directed[(p, q)] += 1
            neighbours[p].add(q)
            neighbours[q].add(p)
    if any(n != 2 for n in edges.values()):
        raise ValueError('Mesh has open or non-manifold edges')
    if any(n != directed[(q, p)] for (p, q), n in list(directed.items())):
        raise ValueError('Inconsistent triangle winding')
    seen = set()
    pending = [next(iter(vertices))]
    while pending:
        p = pending.pop()
        if p not in seen:
            seen.add(p)
            pending.extend(neighbours[p] - seen)
    if seen != vertices:
        raise ValueError('Mesh has disconnected components')
    bounds = [[min(p[i] for p in vertices), max(p[i] for p in vertices)] for i in range(3)]
    if any(abs(bounds[i][0]) > 1e-4 or abs(bounds[i][1] - size) > 1e-4 for i, size in enumerate((50, 30, 25))):
        raise ValueError('Expected 50x30x25 mm bounds at the origin')
    euler = len(vertices) - len(edges) + count
    if euler != 0:
        raise ValueError('Expected one closed surface with one through-hole')
    expected = (50*30 - math.pi*5**2)*25
    error = abs(volume - expected) / expected
    if error > 0.005:
        raise ValueError('Signed mesh volume differs from expected by over 0.5 percent')
    return {'triangles': count, 'vertices': len(vertices), 'bounds_mm': bounds,
            'closed_edges': True, 'consistent_winding': True, 'connected': True,
            'euler_characteristic': euler, 'volume_mm3': volume,
            'expected_volume_mm3': expected, 'relative_volume_error': error}


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: check-stl.py <cut-box binary STL in millimetres>')
    try:
        print(json.dumps(check(Path(sys.argv[1])), indent=2))
    except (OSError, ValueError, struct.error) as exc:
        raise SystemExit(f'STL check failed: {exc}')
