# 汇集浏览器安装服务的标准库引用。
from functools import partial
from argparse import ArgumentParser
from concurrent.futures import ThreadPoolExecutor
from html import escape
from json import dumps as jdmp, loads as jld
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from math import pi, sin
from plistlib import loads
from shutil import copy2
from socket import AF_INET, SOCK_DGRAM, SOCK_STREAM, socket
from sqlite3 import connect
from subprocess import run
from tempfile import TemporaryDirectory
from threading import Event, Thread
from struct import pack
from urllib.parse import quote, urlencode
from urllib.request import urlopen
from wave import open as wavopen

ROOT = Path(__file__).resolve().parent.parent
