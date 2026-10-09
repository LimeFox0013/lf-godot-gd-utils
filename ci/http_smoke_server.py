"""Tiny HTTP/1.1 server for ci/http_smoke.sh (standard library only, loopback only).

Routes: /big (5 MiB), /small, /echo (the request headers as JSON), /redir (302 to
http://localhost:PORT/echo, a different origin). The chosen port is written to argv[1].

It listens on 127.0.0.1 and, when the machine has one, on [::1] at the same port, because
`localhost` may resolve to either address first and the redirect must work with both.
"""
import json
import socket
import socketserver
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, status, body, ctype="application/octet-stream", extra=()):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in extra:
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        try:
            if self.path == "/big":
                self._send(200, b"x" * (5 * 1024 * 1024))
            elif self.path == "/small":
                self._send(200, b"hello")
            elif self.path == "/echo":
                headers = {k.lower(): v for k, v in self.headers.items()}
                self._send(200, json.dumps(headers).encode(), "application/json")
            elif self.path == "/redir":
                port = self.server.server_address[1]
                self._send(302, b"", extra=[("Location", "http://localhost:%d/echo" % port)])
            else:
                self._send(404, b"")
        except (BrokenPipeError, ConnectionResetError):
            pass  # the client gave up (a size limit) before the body ended

    def handle(self):
        try:
            super().handle()
        except ConnectionError:
            pass  # the client closed the connection

    def log_message(self, *args):
        pass


class LoopbackServer(ThreadingHTTPServer):
    # http.server's own server_bind() asks socket.getfqdn() for the host name: a reverse DNS
    # lookup that can take many seconds on a CI runner. Nothing here needs the name.
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name = "localhost"
        self.server_port = self.server_address[1]


class Ipv6Server(LoopbackServer):
    address_family = socket.AF_INET6


server = LoopbackServer(("127.0.0.1", 0), Handler)
port = server.server_address[1]
try:
    ipv6_server = Ipv6Server(("::1", port), Handler)
    threading.Thread(target=ipv6_server.serve_forever, daemon=True).start()
except OSError:
    pass  # no IPv6 loopback, or the port is taken there: `localhost` can only be IPv4
with open(sys.argv[1], "w") as f:
    f.write(str(port))
server.serve_forever()
