"""Persistent Kokoro server so a render loads the model once, not once per narration line.

`am video` spawns `espeak-ng` once per line. Spawning a fresh Python process each time
re-imports torch and reloads Kokoro (several seconds, and a CUDA context on GPU), which
dominated narration time. This server keeps the pipelines warm; `bin/espeak-ng` forwards each
line here over a Unix socket and falls back to the one-shot CLI when no server is running.

Protocol: one JSON line per connection, {"lang", "text", "out"}; reply "ok\n" or "error: ...\n".
Usage: python tts_server.py <socket_path> [lang ...]   (langs to preload: en-us, cmn, ja)
"""

import json
import os
import socketserver
import sys
import threading
import traceback

import kokoro_tts

# One synthesis at a time: a single GPU (or a multi-threaded CPU torch) gains nothing from
# interleaving requests, and Kokoro pipelines are not documented as thread-safe.
SYNTH_LOCK = threading.Lock()


class Handler(socketserver.StreamRequestHandler):
    def handle(self) -> None:
        try:
            request = json.loads(self.rfile.readline())
            with SYNTH_LOCK:
                kokoro_tts.write_wav(request["lang"], request["text"], request["out"])
            self.wfile.write(b"ok\n")
        except Exception as exc:  # report every failure to the client instead of hanging it
            traceback.print_exc()
            self.wfile.write(f"error: {exc}\n".encode())


class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


def main() -> None:
    socket_path, preload = sys.argv[1], sys.argv[2:]
    if os.path.exists(socket_path):
        os.unlink(socket_path)
    for lang in preload:
        kokoro_tts.pipeline_for(lang)
    print(f"tts server ready on {socket_path} (device={kokoro_tts.tts_device()})", flush=True)
    with Server(socket_path, Handler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
