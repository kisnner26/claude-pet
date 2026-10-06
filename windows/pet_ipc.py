"""authenticated local transport; messages are bytes, never pickle objects."""

import csv
import hashlib
from multiprocessing.connection import Client, Listener
import os
from pathlib import Path
import secrets
import subprocess
import threading

from pet_state import Event
from pet_bus import PeerMessage


class LocalListener:
    """hold a process lock for the lifetime of the local endpoint."""

    def __init__(self, listener, lock):
        self.listener = listener
        self.lock = lock
        self.closed = False

    def accept(self):
        return self.listener.accept()

    def close(self):
        self.closed = True
        self.listener.close()
        self.lock.close()


def instance_lock(root):
    handle = open(root / "windows-pet.lock", "a+b")
    handle.seek(0, os.SEEK_END)
    if handle.tell() == 0:
        handle.write(b"0")
        handle.flush()
    handle.seek(0)
    try:
        if os.name == "nt":
            import msvcrt
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as error:
        handle.close()
        raise RuntimeError("claude-pet ya está abierto") from error
    return handle


def private_directory(root):
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    if os.name == "nt":
        hidden = subprocess.CREATE_NO_WINDOW
        identity = subprocess.check_output(
            ["whoami", "/user", "/fo", "csv", "/nh"], text=True, creationflags=hidden)
        sid = next(csv.reader(identity.strip().splitlines()))[1]
        subprocess.run(["icacls", str(root), "/inheritance:r", "/grant:r",
                        f"*{sid}:(OI)(CI)F"], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=hidden)
    else:
        root.chmod(0o700)


def endpoint(root):
    digest = hashlib.sha256(str(root.resolve()).encode()).hexdigest()[:24]
    if os.name == "nt":
        return rf"\\.\pipe\claude-pet-{digest}", "AF_PIPE"
    return str(root / "windows-pet.sock"), "AF_UNIX"


def start_server(root, on_event):
    root = Path(root)
    private_directory(root)
    lock = instance_lock(root)
    address, family = endpoint(root)
    key_path = root / "windows-pet.key"
    # preserve the key across restarts so installed hooks need no rewriting.
    try:
        fd = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        key = key_path.read_bytes()
    else:
        key = secrets.token_bytes(32)
        with os.fdopen(fd, "wb") as handle:
            handle.write(key)
    if len(key) != 32:
        lock.close()
        raise ValueError("invalid local authentication key")
    try:
        if family == "AF_UNIX":
            Path(address).unlink(missing_ok=True)
        listener = LocalListener(Listener(address, family=family, authkey=key), lock)
    except Exception:
        lock.close()
        raise

    def serve():
        while True:
            try:
                connection = listener.accept()
            except (OSError, EOFError):
                if listener.closed:
                    return
                continue
            except Exception:
                continue
            with connection:
                try:
                    if not connection.poll(1):
                        continue
                    message = connection.recv_bytes(2048).decode("utf-8")
                    event = PeerMessage.parse(message) if message.startswith("{") else Event.parse(message)
                    if event:
                        on_event(event)
                except (OSError, EOFError, UnicodeError):
                    pass

    threading.Thread(target=serve, daemon=True).start()
    return listener


def send(root, message):
    root = Path(root)
    address, family = endpoint(root)
    key = (root / "windows-pet.key").read_bytes()
    payload = message.encode("utf-8")
    if len(payload) > 2048:
        raise ValueError("event exceeds local transport limit")
    with Client(address, family=family, authkey=key) as connection:
        connection.send_bytes(payload)
