#!/usr/bin/env python3
# 复用浏览器安装流程，分发当前TrollTask安装包。
from head import (
    AF_INET, SOCK_DGRAM, ROOT, ArgumentParser, Path, SimpleHTTPRequestHandler, ThreadingHTTPServer,
    TemporaryDirectory, copy2, escape, loads, partial, quote, run, socket, urlencode,
)


# 读取局域网地址。
def lclip():
    for iface in ("en0", "en1"):
        result = run(["/usr/sbin/ipconfig", "getifaddr", iface], capture_output=True, text=True)
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    with socket(AF_INET, SOCK_DGRAM) as sock:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]


# 关闭安装页与安装包的浏览器缓存。
class Hnd(SimpleHTTPRequestHandler):
    timeout = 30

    # 禁用安装页与包的浏览器缓存。
    def end_headers(self):
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()


# 并发响应浏览器预连接和安装包下载。
class Srv(ThreadingHTTPServer):
    allow_reuse_address = True


# 在独立临时目录和固定端口提供浏览器安装入口。
def srvmain(pkg=None):
    cfg = loads((ROOT / "Resources/Info.plist").read_bytes())
    pkg = pkg or ROOT / "build" / f"{cfg['CFBundleExecutable']}-{cfg['CFBundleShortVersionString']}.tipa"
    ip = lclip()
    assets = ROOT / "Resources/Installer"
    with TemporaryDirectory(prefix="trolltask-install-") as stage:
        copy2(pkg, Path(stage) / pkg.name)
        copy2(assets / "install.mjs", Path(stage) / "install.mjs")
        handler = partial(Hnd, directory=stage)
        with Srv(("0.0.0.0", 61265), handler) as server:
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
    parser = ArgumentParser()
    parser.add_argument("--package", type=Path)
    srvmain(parser.parse_args().package)
