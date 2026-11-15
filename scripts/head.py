# 汇集脚本与测试的标准库引用。
from datetime import datetime, timezone
from functools import partial
from argparse import ArgumentParser
from concurrent.futures import ThreadPoolExecutor
from html import escape
from json import dumps as jdmp, loads as jld
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from plistlib import dumps as pl_dumps, loads
from re import fullmatch
from shutil import copy2
from socket import AF_INET, SOCK_DGRAM, SOCK_STREAM, socket
from sqlite3 import connect
from subprocess import run
from tempfile import TemporaryDirectory
from threading import Event, Thread
from sys import argv
from urllib.parse import quote, urlencode
from urllib.request import urlopen
from uuid import UUID

ROOT = Path(__file__).resolve().parent.parent
