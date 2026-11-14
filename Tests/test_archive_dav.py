# 在随机回环端口提供真实WebDAV请求夹具。
from base64 import b64encode
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path, PurePosixPath
import re
import sys
from urllib.parse import unquote, urlsplit


class ArchiveDAV(BaseHTTPRequestHandler):
    folders = {"/", "/other", "/readonly"}
    files = {}
    corrupt_once = True
    auth = "Basic " + b64encode(b"test:archive-fixture").decode()

    # 返回完整HTTP响应，固定认证仅供隔离测试。
    def reply(self, status, body=b""):
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # 解码请求路径并核对认证。
    def target(self):
        if self.headers.get("Authorization") != self.auth:
            self.reply(401)
            return None
        return unquote(urlsplit(self.path).path).rstrip("/") or "/"

    def do_PROPFIND(self):
        target = self.target()
        if target is not None:
            if target in self.folders and self.headers.get("Depth") == "0":
                self.reply(207, b'<multistatus xmlns="DAV:"><response><propstat><prop><resourcetype><collection/></resourcetype></prop><status>HTTP/1.1 200 OK</status></propstat></response></multistatus>')
            else:
                self.reply(404)

    def do_MKCOL(self):
        target = self.target()
        if target is not None:
            if target in self.folders:
                self.reply(405)
            elif str(PurePosixPath(target).parent) in self.folders:
                self.folders.add(target)
                self.reply(201)
            else:
                self.reply(409)

    def do_PUT(self):
        target = self.target()
        if target is None:
            return
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if target.startswith("/readonly/") or (target.startswith("/other/") and body.startswith(b'{') and b'fallback fixture' in body):
            self.reply(405)
            return
        expected = r"(?:/other)?/TrollTaskArchive/(?:\.trolltask-check|[0-9]{6}/[0-9a-f-]+/[^/]+)"
        if re.fullmatch(expected, target) and str(PurePosixPath(target).parent) in self.folders:
            self.files[target] = body
            self.reply(201)
        else:
            self.reply(409)

    def do_GET(self):
        target = self.target()
        if target is None:
            return
        if target not in self.files:
            self.reply(404)
        elif "附件" in target and type(self).corrupt_once:
            type(self).corrupt_once = False
            self.reply(200, b"corrupted")
        else:
            self.reply(200, self.files[target])

    def do_DELETE(self):
        target = self.target()
        if target is not None:
            self.reply(204 if self.files.pop(target, None) is not None else 404)

if __name__ == "__main__":
    host = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
    with HTTPServer((host, 0), ArchiveDAV) as server:
        Path(sys.argv[1]).write_text(str(server.server_port))
        server.serve_forever()
