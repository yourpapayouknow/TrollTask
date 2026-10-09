# 汇集浏览器安装服务的标准库引用。
from functools import partial
from html import escape
from json import dumps as jdmp, loads as jld
from http.server import SimpleHTTPRequestHandler
from pathlib import Path
from plistlib import loads
from shutil import copy2
from socket import AF_INET, SOCK_DGRAM, socket
from socketserver import TCPServer
from sqlite3 import connect
from subprocess import run
from tempfile import TemporaryDirectory
from urllib.parse import quote, urlencode

ROOT = Path(__file__).resolve().parent.parent
