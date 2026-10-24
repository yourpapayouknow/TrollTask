# 验证空闲连接不会阻塞安装页及安装包下载。
from head import (
    AF_INET, SOCK_STREAM, ROOT, Path, TemporaryDirectory, Event, Thread,
    ThreadPoolExecutor, partial, socket, urlopen, loads,
)
from serve import Hnd, Srv


# 在真实连接中重现浏览器预连接和未完成请求。
def tstsrv():
    accepted = Event()

    # 标记服务实际接收了测试连接。
    class Prb(Hnd):
        # 等待请求处理开始。
        def setup(self):
            super().setup()
            accepted.set()

    cfg = loads((ROOT / 'Resources/Info.plist').read_bytes())
    name = f"{cfg['CFBundleExecutable']}-{cfg['CFBundleShortVersionString']}.tipa"
    files = {
        '/': b'<html>Installer</html>',
        '/install.mjs': (ROOT / 'Resources/Installer/install.mjs').read_bytes(),
        '/' + name: (ROOT / 'build' / name).read_bytes(),
    }
    with TemporaryDirectory(prefix='trolltask-http-test-') as stage:
        for path, body in files.items():
            (Path(stage) / (path.lstrip('/') or 'index.html')).write_bytes(body)
        with Srv(('127.0.0.1', 0), partial(Prb, directory=stage)) as server:
            worker = Thread(target=server.serve_forever, daemon=True)
            worker.start()
            clients = []
            base = f'http://127.0.0.1:{server.server_address[1]}'
            try:
                idle = socket(AF_INET, SOCK_STREAM)
                clients.append(idle)
                idle.connect(server.server_address)
                assert accepted.wait(2), '预连接未被服务接收'
                with urlopen(base, timeout=1) as response:
                    assert response.status == 200, '预连接阻塞了安装页'
                accepted.clear()
                incomplete = socket(AF_INET, SOCK_STREAM)
                clients.append(incomplete)
                incomplete.connect(server.server_address)
                assert accepted.wait(2), '未完成请求未被服务接收'
                incomplete.sendall(b'GET / HTTP/1.1\r\nHost: localhost\r\n')
                for path, expected in files.items():
                    with urlopen(base + path, timeout=1) as response:
                        assert response.status == 200
                        assert 'no-store' in response.headers['Cache-Control']
                        assert response.read() == expected

                # 同时下载同一安装包并验证内容完整。
                def ftch(_):
                    with urlopen(base + '/' + name, timeout=2) as response:
                        assert response.read() == files['/' + name]

                with ThreadPoolExecutor(max_workers=8) as pool:
                    list(pool.map(ftch, range(8)))
                Prb.timeout = 0.1
                expired = socket(AF_INET, SOCK_STREAM)
                clients.append(expired)
                expired.settimeout(2)
                expired.connect(server.server_address)
                assert expired.recv(1) == b'', '空闲连接未超时关闭'
            finally:
                for client in clients:
                    client.close()
                server.shutdown()
                worker.join(2)
                assert not worker.is_alive(), '分发服务无法停止'
    print('安装分发测试通过：预连接、未完成请求、网页/脚本/包、8并发下载、空闲超时与停止。')


# 运行安装分发回归检查。
if __name__ == '__main__':
    tstsrv()
