#!/usr/bin/env python3
"""nodes.auto.tfvars aus nodes.auto.tfvars.example erzeugen.

Ersetzt genau die vier Stellen, die pro Host anders sind. Alles andere
(Adressplan, RAM-Tarife, enabled-Flags) bleibt im Beispiel und damit im Git.

  ./make-tfvars.py --endpoint https://192.168.178.10:8006/ \
      --token 'tofu@pve!opentofu=...' --node hl0 \
      --ssh-key "$(cut -d' ' -f1,2 /root/.ssh/authorized_keys | head -1)"
"""
from __future__ import annotations
import argparse, re, sys
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--example", default="nodes.auto.tfvars.example")
    ap.add_argument("--out", default="nodes.auto.tfvars")
    ap.add_argument("--endpoint", required=True)
    ap.add_argument("--token", required=True)
    ap.add_argument("--node", required=True)
    ap.add_argument("--ssh-key", required=True)
    a = ap.parse_args()

    src = Path(a.example).read_text()

    def sub(pattern: str, repl: str, text: str, what: str) -> str:
        new, n = re.subn(pattern, repl, text, count=1, flags=re.M)
        if n != 1:
            sys.exit(f"Konnte {what} nicht ersetzen ({pattern!r})")
        return new

    src = sub(r'^\s*endpoint\s*=\s*".*"$',  f'  endpoint  = "{a.endpoint}"', src, "endpoint")
    src = sub(r'^\s*api_token\s*=\s*".*"$', f'  api_token = "{a.token}"', src, "api_token")
    src = sub(r'^\s*node\s*=\s*".*"$',      f'  node         = "{a.node}"', src, "node")
    src = sub(r'^\s*ssh_keys\s*=\s*\[.*\]$',
              f'  ssh_keys     = ["{a.ssh_key}"]', src, "ssh_keys")

    for marker in ("PLATZHALTER", "DEIN-PUBLIC-KEY", "BITTE-"):
        if marker in src:
            sys.exit(f"Platzhalter {marker!r} steht noch in der Datei")
    Path(a.out).write_text(src)
    print(f"{a.out} geschrieben (node={a.node}, endpoint={a.endpoint})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
