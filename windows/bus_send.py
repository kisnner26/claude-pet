"""send codex presence; --hold publishes a heartbeat until interrupted."""

import argparse
import json
from pathlib import Path
import time

from pet_ipc import send
from pet_state import PRIORITY


def publish(state, event=None):
    packet = dict(v=1, id="codex", state=state, ts=time.time())
    if event:
        packet["event"] = event
    send(Path.home() / ".claude-pet", json.dumps(packet, separators=(",", ":")))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("state", choices=PRIORITY, default="idle", nargs="?")
    parser.add_argument("--hold", action="store_true")
    args = parser.parse_args()
    publish(args.state, "appeared")
    if args.hold:
        try:
            while True:
                time.sleep(10)
                publish(args.state)
        except KeyboardInterrupt:
            publish("idle", "left")


if __name__ == "__main__":
    main()
