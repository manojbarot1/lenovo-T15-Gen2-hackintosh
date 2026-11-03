"""Remote shell bridge to the T15 in macOS Recovery.

serve: listen on 192.168.1.22:9001 for the T15's outgoing shell connection
       (only from 192.168.1.17) and on a local unix socket for commands.
run:   python3 -I t15link.py run 'command' [timeout] -> prints the command's output.
"""
import os, socket, sys, threading, uuid

HERE = os.path.dirname(os.path.abspath(__file__))
SOCK = os.path.join(HERE, "t15.sock")
T15 = os.environ.get("T15_IP", "192.168.1.17")
conn = None
lock = threading.Lock()


def accept_t15():
    global conn
    srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("192.168.1.22", 9001)); srv.listen(1)
    while True:
        c, addr = srv.accept()
        if addr[0] != T15:
            c.close(); continue
        with lock:
            if conn: conn.close()
            conn = c
        print("T15 connected", addr, flush=True)


def run_on_t15(cmd, timeout):
    global conn
    tag = "__END_" + uuid.uuid4().hex + "__"
    with lock:
        if not conn:
            return "NOT CONNECTED (T15 helper has not called in yet)\n"
        buf = b""
        try:
            conn.settimeout(timeout)
            conn.sendall(f"( {cmd} ) 2>&1; echo {tag} $?\n".encode())
            while tag.encode() not in buf:
                d = conn.recv(65536)
                if not d:
                    return buf.decode(errors="replace") + "\n[connection closed]\n"
                buf += d
        except socket.timeout:
            return buf.decode(errors="replace") + f"\n[timed out after {timeout}s]\n"
        except OSError:
            conn = None
            return buf.decode(errors="replace") + "\n[connection closed]\n"
    out, _, rc = buf.decode(errors="replace").partition(tag)
    return out + f"[exit {rc.strip()}]\n"


def serve():
    threading.Thread(target=accept_t15, daemon=True).start()
    if os.path.exists(SOCK): os.unlink(SOCK)
    s = socket.socket(socket.AF_UNIX); s.bind(SOCK); os.chmod(SOCK, 0o600); s.listen(4)
    while True:
        c, _ = s.accept()
        req = c.makefile("rb").readline().decode()
        timeout, _, cmd = req.partition(" ")
        c.sendall(run_on_t15(cmd.rstrip("\n"), int(timeout)).encode()); c.close()


def run(cmd, timeout=60):
    s = socket.socket(socket.AF_UNIX); s.connect(SOCK)
    s.sendall(f"{timeout} {cmd}\n".encode())
    sys.stdout.write(s.makefile("rb").read().decode())


if __name__ == "__main__":
    if sys.argv[1] == "serve": serve()
    else: run(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 60)
