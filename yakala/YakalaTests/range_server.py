"""Static file server with HTTP Range support, for Yakala integration tests.

Usage: python3 range_server.py <directory> <port> [throttle]

With `throttle` N, the first N requests for .ts segments get 429 + Retry-After: 1.
"""
import os
import re
import sys
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

THROTTLE = {"left": 0}
LOCK = threading.Lock()


class RangeHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_head(self):
        if self.path.endswith(".ts"):
            with LOCK:
                limited = THROTTLE["left"] > 0
                if limited:
                    THROTTLE["left"] -= 1
            if limited:
                self.send_response(429)
                self.send_header("Retry-After", "1")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return None
        path = self.translate_path(self.path)
        rng = self.headers.get("Range")
        if not rng or not os.path.isfile(path):
            return super().send_head()
        m = re.match(r"bytes=(\d+)-(\d*)", rng)
        size = os.path.getsize(path)
        start = int(m.group(1))
        end = int(m.group(2)) if m.group(2) else size - 1
        end = min(end, size - 1)
        f = open(path, "rb")
        f.seek(start)
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Length", str(end - start + 1))
        self.end_headers()
        self._remaining = end - start + 1
        return f

    def copyfile(self, source, outputfile):
        remaining = getattr(self, "_remaining", None)
        if remaining is None:
            return super().copyfile(source, outputfile)
        while remaining > 0:
            chunk = source.read(min(65536, remaining))
            if not chunk:
                break
            outputfile.write(chunk)
            remaining -= len(chunk)


if __name__ == "__main__":
    os.chdir(sys.argv[1])
    THROTTLE["left"] = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[2])), RangeHandler).serve_forever()
