#!/usr/bin/env python3
"""Build the requested single-file HTML preview without external dependencies."""
from pathlib import Path

root = Path(__file__).resolve().parent
html = (root / "index.html").read_text(encoding="utf-8")
css = (root / "styles.css").read_text(encoding="utf-8")
js = (root / "app.js").read_text(encoding="utf-8")
assert '</script' not in js.lower(), "Escape closing script tags before inlining"
assert '</style' not in css.lower(), "Escape closing style tags before inlining"
html = html.replace('<link rel="stylesheet" href="styles.css">', '<style>\n' + css + '\n</style>')
html = html.replace('<script src="app.js"></script>', '<script>\n' + js + '\n</script>')
output = root / "VietMap-demo.html"
output.write_text(html, encoding="utf-8")
print(f"Created {output.name}: {output.stat().st_size:,} bytes, self-contained")
