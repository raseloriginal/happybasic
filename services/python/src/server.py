from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import platform


def load_env(env_path: Path) -> None:
    if not env_path.is_file():
        return
    for raw in env_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        key = key.strip()
        val = val.strip().strip('"').strip("'")
        os.environ.setdefault(key, val)


ROOT_ENV = Path(__file__).resolve().parents[3] / ".env"
load_env(ROOT_ENV)

PORT = int(os.environ.get("SERVICE_PYTHON_PORT", "8001"))
SERVICE_TOKEN = os.environ.get("INTERNAL_SERVICE_TOKEN", "")


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=UTF-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if SERVICE_TOKEN and self.headers.get("X-Service-Token") != SERVICE_TOKEN:
            self._send_json(401, {"error": "Unauthorized service token"})
            return

        if self.path.split("?", 1)[0] == "/health":
            self._send_json(200, {
                "status": "ok",
                "service": "python",
                "runtime": platform.python_version(),
            })
            return

        self._send_json(404, {"error": "Not Found"})


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", PORT), Handler)
    print(f"[python] listening on http://127.0.0.1:{PORT}")
    server.serve_forever()
