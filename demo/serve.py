#!/usr/bin/env python3
"""Server tĩnh tối giản cho bản demo giao diện VietMap 3.0.

Khác `python3 -m http.server` ở 3 điểm cần cho môi trường preview:
  * `Content-Type: text/html; charset=utf-8` → tiếng Việt không bị lỗi font.
  * `Cache-Control: no-store` → luôn thấy bản demo mới nhất sau khi sửa file.
  * Đường dẫn lạ (ví dụ proxy thêm tiền tố) đều trả `index.html`.

Cách dùng:
    python3 demo/serve.py            # cổng 8000
    python3 demo/serve.py 8080       # cổng khác
"""
from __future__ import annotations

import os
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.abspath(__file__))
MIME = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".ico": "image/x-icon",
}


class DemoHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    # ---- tiêu đề HTTP ----
    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store, must-revalidate")
        self.send_header("X-Content-Type-Options", "nosniff")
        # Không chặn nhúng iframe: preview của Arena hiển thị trang trong khung.
        super().end_headers()

    def guess_type(self, path):  # noqa: D102 - ghi đè để luôn có charset
        ext = os.path.splitext(str(path))[1].lower()
        return MIME.get(ext, super().guess_type(path))

    # ---- định tuyến: mọi đường dẫn không phải file → index.html ----
    def translate_path(self, path: str) -> str:
        resolved = super().translate_path(path)
        if os.path.exists(resolved):
            return resolved
        return os.path.join(ROOT, "index.html")

    def do_GET(self) -> None:  # noqa: N802
        if self.path.split("?")[0] in ("", "/"):
            self.path = "/index.html"
        super().do_GET()

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    server = ThreadingHTTPServer(("0.0.0.0", port), DemoHandler)
    print(f"Demo VietMap 3.0 → http://0.0.0.0:{port}  (root: {ROOT})", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
