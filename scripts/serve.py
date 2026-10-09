#!/usr/bin/env python3
# 复用原工程的浏览器安装流程，分发当前TrollTask安装包。
from head import (
    AF_INET, SOCK_DGRAM, ROOT, Path, SimpleHTTPRequestHandler, TCPServer,
    TemporaryDirectory, copy2, escape, loads, partial, quote, run, socket, urlencode,
)


# 沿用原工程方法读取局域网地址。
def lclip():
    for iface in ("en0", "en1"):
        result = run(["/usr/sbin/ipconfig", "getifaddr", iface], capture_output=True, text=True)
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    with socket(AF_INET, SOCK_DGRAM) as sock:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]


# 保留原工程的安装页缓存策略。
class Hnd(SimpleHTTPRequestHandler):
    # 禁用安装页与包的浏览器缓存。
    def end_headers(self):
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()


# 在独立临时目录和空闲端口提供浏览器安装入口。
def srvmain():
    cfg = loads((ROOT / "Resources/Info.plist").read_bytes())
    pkg = ROOT / "build" / f"{cfg['CFBundleExecutable']}-{cfg['CFBundleShortVersionString']}.tipa"
    ip = lclip()
    assets = ROOT / "Resources/Installer"
    with TemporaryDirectory(prefix="trolltask-install-") as stage:
        copy2(pkg, Path(stage) / pkg.name)
        copy2(assets / "install.mjs", Path(stage) / "install.mjs")
        handler = partial(Hnd, directory=stage)
        with TCPServer(("0.0.0.0", 0), handler) as server:
            url = f"http://{ip}:{server.server_address[1]}"
            pkgurl = f"{url}/{quote(pkg.name)}"
            insturl = "apple-magnifier://install?" + urlencode({"url": pkgurl})
            html = (assets / "index.html").read_text()
            html = html.replace("{{INSTALL_URL}}", escape(insturl, quote=True))
            html = html.replace("{{PACKAGE_URL}}", escape(pkgurl, quote=True))
            (Path(stage) / "index.html").write_text(html)
            print(f"手机Safari打开：{url}/", flush=True)
            print(f"安装包：{pkgurl}", flush=True)
            print("按Ctrl+C停止服务", flush=True)
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                print("服务已停止", flush=True)


# 启动浏览器安装服务。
if __name__ == "__main__":
    srvmain()
