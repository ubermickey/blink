#!/usr/bin/env python3

import argparse
import json
import os
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class FixtureHelperHandler(BaseHTTPRequestHandler):
  server_version = "BlinkFixtureHelper/1.0"

  def _write_json(self, payload, code=HTTPStatus.OK):
    body = json.dumps(payload, sort_keys=True).encode("utf-8")
    self.send_response(code)
    self.send_header("Content-Type", "application/json")
    self.send_header("Content-Length", str(len(body)))
    self.end_headers()
    self.wfile.write(body)

  def do_GET(self):  # noqa: N802
    if self.path in ("/healthz", "/health"):
      self._write_json({"ok": True, "service": "fixture-helper"})
      return

    if self.path in ("/meta", "/"):
      payload = {
        "ok": True,
        "service": "fixture-helper",
        "run_id": self.server.run_id,
        "lane": self.server.lane,
        "remote_root": self.server.remote_root,
        "timestamp": int(time.time()),
      }
      self._write_json(payload)
      return

    self._write_json({"ok": False, "error": "not_found"}, code=HTTPStatus.NOT_FOUND)

  def log_message(self, format, *args):  # noqa: A003
    return


def parse_args():
  parser = argparse.ArgumentParser(description="Blink fixture helper service")
  parser.add_argument("--bind", default=os.environ.get("FIXTURE_HELPER_BIND", "127.0.0.1"))
  parser.add_argument("--port", type=int, default=int(os.environ.get("FIXTURE_HELPER_PORT", "18080")))
  parser.add_argument("--run-id", default=os.environ.get("FIXTURE_RUN_ID", "legacy"))
  parser.add_argument("--lane", default=os.environ.get("FIXTURE_LANE", "default"))
  parser.add_argument("--remote-root", default=os.environ.get("FIXTURE_REMOTE_ROOT", "~/fps"))
  return parser.parse_args()


def main():
  args = parse_args()
  server = ThreadingHTTPServer((args.bind, args.port), FixtureHelperHandler)
  server.run_id = args.run_id
  server.lane = args.lane
  server.remote_root = args.remote_root
  server.serve_forever()


if __name__ == "__main__":
  main()
