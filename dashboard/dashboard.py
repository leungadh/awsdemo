#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "aiohttp>=3.9",
#   "asyncssh>=2.14",
#   "boto3>=1.34",
#   "pyyaml>=6.0",
# ]
# ///
"""
vSRX Security Demo Dashboard

Polls the vSRX via SSH and AWS API, then pushes live state to a browser
over WebSocket so the operator sees topology, attack events, and counters
without opening a terminal.

Usage:
  pip install -r requirements.txt
  cd dashboard && python dashboard.py
  Open http://localhost:8080
"""

import asyncio
import copy
import json
import os
import re
import subprocess
import webbrowser
from datetime import datetime, timezone
from pathlib import Path

import aiohttp
import asyncssh
import boto3
import yaml
from aiohttp import web


# ── Junos CLI output parsers ──────────────────────────────────────────────────

RE_SCREEN = {
    "port_scan":   re.compile(r"TCP port scan:\s+(\d+)", re.I),
    "syn_flood":   re.compile(r"TCP SYN flood:\s+(\d+)", re.I),
    "icmp_flood":  re.compile(r"ICMP flood:\s+(\d+)", re.I),
    "ip_spoofing": re.compile(r"IP spoofing:\s+(\d+)", re.I),
}

# Count lines in `show security idp attack table` matching each attack group
RE_IDP_SSH  = re.compile(r"\bSSH\b", re.I)
RE_IDP_HTTP = re.compile(r"\bHTTP\b", re.I)
RE_IDP_SQL  = re.compile(r"\bSQL\b", re.I)

RE_SESSION  = re.compile(r"Total sessions:\s+(\d+)", re.I)
# demo-policy hit-count line: "  4   untrust   trust   demo-policy   0   <HITS>"
RE_POLICY   = re.compile(r"demo-policy\s+\d+\s+(\d+)", re.I)
# Physical interface terse: "ge-0/0/0   up   up"  (stops matching on "ge-0/0/0.0" due to ".")
RE_IFACE    = re.compile(r"^(ge-0/0/\d+)\s+(up|down)\s+(up|down)", re.I | re.M)


def parse_screen(text: str) -> dict:
    return {k: int(m.group(1)) if (m := p.search(text)) else 0
            for k, p in RE_SCREEN.items()}


def parse_idp(text: str) -> dict:
    # Skip header lines (first 2 lines) to avoid matching column headers
    data_lines = text.splitlines()[2:]
    return {
        "ssh_brute":    sum(1 for l in data_lines if RE_IDP_SSH.search(l)),
        "http_attacks": sum(1 for l in data_lines if RE_IDP_HTTP.search(l)),
        "sql_injection": sum(1 for l in data_lines if RE_IDP_SQL.search(l)),
    }


def parse_sessions(text: str) -> int:
    m = RE_SESSION.search(text)
    return int(m.group(1)) if m else 0


def parse_policy_hits(text: str) -> int:
    m = RE_POLICY.search(text)
    return int(m.group(1)) if m else 0


def parse_interfaces(ge0_text: str, ge1_text: str) -> dict:
    result = {}
    for iface, text in [("ge-0/0/0", ge0_text), ("ge-0/0/1", ge1_text)]:
        m = RE_IFACE.search(text)
        result[iface] = (m.group(3).lower() == "up") if m else False
    return result


# ── State helpers ─────────────────────────────────────────────────────────────

def empty_state() -> dict:
    return {
        "timestamp": "",
        "poll_status": "connecting",
        "nodes": {
            "kali": {
                "status": "unknown",
                "instance_state": "unknown",
                "public_ip": "",
            },
            "vsrx": {
                "status": "unknown",
                "instance_state": "unknown",
                "public_ip": "",
                "ge0_up": False,
                "ge1_up": False,
            },
            "webserver": {
                "status": "unknown",
                "instance_state": "unknown",
                "web_reachable": False,
            },
        },
        "links": {
            "kali_to_vsrx": {"status": "healthy"},
            "vsrx_to_web":  {"status": "healthy"},
        },
        "screen_counters": {
            "port_scan": 0, "syn_flood": 0, "icmp_flood": 0, "ip_spoofing": 0,
        },
        "idp_hits": {
            "ssh_brute": 0, "http_attacks": 0, "sql_injection": 0,
        },
        "screen_deltas": {
            "port_scan": 0, "syn_flood": 0, "icmp_flood": 0, "ip_spoofing": 0,
        },
        "idp_deltas": {
            "ssh_brute": 0, "http_attacks": 0, "sql_injection": 0,
        },
        "session_summary": {"active_sessions": 0},
        "policy_hit_count": 0,
        "recent_logs": [],
    }


def derive_status(state: dict, prev: dict, attack_sticky: dict) -> None:
    """Compute node/link status from counters; mutates state in-place."""
    sc = state["screen_counters"]
    pc = prev["screen_counters"]
    ic = state["idp_hits"]
    pi = prev["idp_hits"]

    screen_deltas = {k: max(0, sc[k] - pc[k]) for k in sc}
    idp_deltas    = {k: max(0, ic[k] - pi[k]) for k in ic}

    state["screen_deltas"] = screen_deltas
    state["idp_deltas"]    = idp_deltas

    # Sticky attack: keep "attack" state for 2 more poll cycles after last hit
    if any(v > 0 for v in screen_deltas.values()):
        attack_sticky["kali_vsrx"] = 2
    elif attack_sticky.get("kali_vsrx", 0) > 0:
        attack_sticky["kali_vsrx"] -= 1

    if any(v > 0 for v in idp_deltas.values()):
        attack_sticky["vsrx_web"] = 2
    elif attack_sticky.get("vsrx_web", 0) > 0:
        attack_sticky["vsrx_web"] -= 1

    kali_sticky = attack_sticky.get("kali_vsrx", 0) > 0
    web_sticky  = attack_sticky.get("vsrx_web", 0) > 0

    # vSRX status
    vsrx = state["nodes"]["vsrx"]
    if vsrx["instance_state"] not in ("running", "unknown"):
        vsrx["status"] = "stopped"
    elif kali_sticky or web_sticky:
        vsrx["status"] = "attack"
    elif not vsrx["ge0_up"] or not vsrx["ge1_up"]:
        vsrx["status"] = "warning"
    else:
        vsrx["status"] = "healthy"

    # Web server status
    web = state["nodes"]["webserver"]
    if web["instance_state"] not in ("running", "unknown"):
        web["status"] = "stopped"
    elif web_sticky:
        web["status"] = "attack"
    elif not web["web_reachable"]:
        web["status"] = "warning"
    else:
        web["status"] = "healthy"

    # Kali status
    kali = state["nodes"]["kali"]
    kali["status"] = (
        "healthy" if kali["instance_state"] == "running"
        else "stopped" if kali["instance_state"] in ("stopped", "terminated")
        else "unknown"
    )

    state["links"]["kali_to_vsrx"]["status"] = "attack" if kali_sticky else "healthy"
    state["links"]["vsrx_to_web"]["status"]  = "attack" if web_sticky  else "healthy"


# ── SSH Poller ────────────────────────────────────────────────────────────────

class SSHPoller:
    def __init__(self, cfg: dict):
        self.host     = cfg["vsrx_public_ip"]
        self.user     = cfg.get("ssh_user", "ec2-user")
        self.key_path = str(Path(cfg["ssh_key_path"]).expanduser())
        self._conn    = None

    async def _connect(self):
        self._conn = await asyncssh.connect(
            self.host,
            username=self.user,
            client_keys=[self.key_path],
            known_hosts=None,   # demo lab: IPs change on each terraform apply
            connect_timeout=15,
        )

    async def _run(self, cmd: str, timeout: int = 10) -> str:
        try:
            result = await asyncio.wait_for(self._conn.run(f"{cmd} | no-more"), timeout=timeout)
            return result.stdout or ""
        except Exception:
            return ""

    async def _ensure_connected(self):
        if self._conn is None or self._conn.is_closing():
            await self._connect()

    async def poll(self) -> dict | None:
        for attempt in range(2):
            try:
                await self._ensure_connected()

                screen_out  = await self._run("show security screen statistics interface ge-0/0/0")
                idp_out     = await self._run("show security idp attack table")
                session_out = await self._run("show security flow session summary")
                policy_out  = await self._run(
                    "show security policies hit-count from-zone untrust to-zone trust"
                )
                log_out = await self._run("show log security-log | last 20")
                ge0_out = await self._run("show interfaces ge-0/0/0 terse")
                ge1_out = await self._run("show interfaces ge-0/0/1 terse")

                ifaces = parse_interfaces(ge0_out, ge1_out)
                return {
                    "screen":      parse_screen(screen_out),
                    "idp":         parse_idp(idp_out),
                    "sessions":    parse_sessions(session_out),
                    "policy_hits": parse_policy_hits(policy_out),
                    "logs":        [l.strip() for l in log_out.splitlines() if l.strip()][-20:],
                    "ge0_up":      ifaces.get("ge-0/0/0", False),
                    "ge1_up":      ifaces.get("ge-0/0/1", False),
                }
            except (asyncssh.Error, OSError, asyncio.TimeoutError):
                self._conn = None
                if attempt == 0:
                    await asyncio.sleep(2)
                else:
                    return None
        return None

    async def run_reset(self) -> None:
        for attempt in range(2):
            try:
                await self._ensure_connected()
                await self._run("clear security screen statistics")
                await self._run("clear security idp counters")
                return
            except (asyncssh.Error, OSError):
                self._conn = None
                if attempt == 0:
                    await asyncio.sleep(2)


# ── AWS Poller ────────────────────────────────────────────────────────────────

class AWSPoller:
    _TAG_MAP = {
        "demo-vsrx":      "vsrx",
        "demo-kali":      "kali",
        "demo-webserver": "webserver",
    }

    def __init__(self, cfg: dict):
        self._ec2 = boto3.client("ec2", region_name=cfg.get("aws_region", "ap-southeast-1"))

    async def poll(self) -> dict:
        def _call():
            return self._ec2.describe_instances(
                Filters=[{"Name": "tag:Name", "Values": list(self._TAG_MAP.keys())}]
            )
        try:
            response = await asyncio.to_thread(_call)
        except Exception:
            return {}

        result = {}
        for reservation in response.get("Reservations", []):
            for inst in reservation.get("Instances", []):
                tag_name = next(
                    (t["Value"] for t in inst.get("Tags", []) if t["Key"] == "Name"), ""
                )
                key = self._TAG_MAP.get(tag_name)
                if key:
                    result[key] = {
                        "instance_state": inst.get("State", {}).get("Name", "unknown"),
                        "public_ip":      inst.get("PublicIpAddress", ""),
                    }
        return result


# ── Dashboard application ─────────────────────────────────────────────────────

class Dashboard:
    def __init__(self, cfg: dict):
        self.cfg           = cfg
        self.state         = empty_state()
        self.prev_state    = empty_state()
        self.attack_sticky: dict = {}
        self.ws_clients:   set  = set()
        self.ssh           = SSHPoller(cfg)
        self.aws           = AWSPoller(cfg)

    async def _broadcast(self):
        payload = json.dumps(self.state)
        dead = set()
        for ws in self.ws_clients:
            try:
                await ws.send_str(payload)
            except Exception:
                dead.add(ws)
        self.ws_clients -= dead

    async def _do_poll(self):
        self.prev_state = copy.deepcopy(self.state)

        data = await self.ssh.poll()
        if data is None:
            self.state["poll_status"] = "ssh_error"
        else:
            self.state["poll_status"]  = "ok"
            self.state["screen_counters"]                     = data["screen"]
            self.state["idp_hits"]                            = data["idp"]
            self.state["session_summary"]["active_sessions"]  = data["sessions"]
            self.state["policy_hit_count"]                    = data["policy_hits"]
            self.state["recent_logs"]                         = data["logs"]
            self.state["nodes"]["vsrx"]["ge0_up"] = data["ge0_up"]
            self.state["nodes"]["vsrx"]["ge1_up"] = data["ge1_up"]

        derive_status(self.state, self.prev_state, self.attack_sticky)
        self.state["timestamp"] = datetime.now(timezone.utc).isoformat()
        await self._broadcast()

    async def _poll_loop(self):
        interval = self.cfg.get("poll_interval_seconds", 15)
        await asyncio.sleep(3)   # let AWS loop run first
        while True:
            await self._do_poll()
            await asyncio.sleep(interval)

    async def _aws_loop(self):
        interval = self.cfg.get("aws_poll_interval_seconds", 30)
        while True:
            data = await self.aws.poll()
            for key, info in data.items():
                if key in self.state["nodes"]:
                    self.state["nodes"][key]["instance_state"] = info["instance_state"]
                    if info.get("public_ip"):
                        self.state["nodes"][key]["public_ip"] = info["public_ip"]
                    # Web server has no public IP and ICMP is blocked by its SG;
                    # use EC2 instance state as the health signal instead.
                    if key == "webserver":
                        self.state["nodes"][key]["web_reachable"] = (
                            info["instance_state"] == "running"
                        )
            await asyncio.sleep(interval)

    # ── HTTP handlers ──────────────────────────────────────────────────────────

    async def handle_index(self, request):
        return web.FileResponse(Path(__file__).parent / "static" / "index.html")

    async def handle_state(self, request):
        return web.json_response(self.state)

    async def handle_reset(self, request):
        await self.ssh.run_reset()
        # Clear our prev-state counters so deltas start from 0
        for k in self.state["screen_counters"]:
            self.prev_state["screen_counters"][k] = self.state["screen_counters"][k]
        for k in self.state["idp_hits"]:
            self.prev_state["idp_hits"][k] = self.state["idp_hits"][k]
        self.attack_sticky.clear()
        await self._do_poll()
        return web.json_response({"ok": True})

    async def handle_ws(self, request):
        ws = web.WebSocketResponse(heartbeat=30)
        await ws.prepare(request)
        self.ws_clients.add(ws)
        await ws.send_str(json.dumps(self.state))
        async for _ in ws:
            pass
        self.ws_clients.discard(ws)
        return ws

    def build_app(self) -> web.Application:
        app = web.Application()
        app.router.add_get("/",                  self.handle_index)
        app.router.add_get("/ws",                self.handle_ws)
        app.router.add_get("/api/state",         self.handle_state)
        app.router.add_post("/api/reset-counters", self.handle_reset)
        static_dir = Path(__file__).parent / "static"
        if static_dir.exists():
            app.router.add_static("/static", static_dir)
        return app

    async def on_startup(self, app):
        asyncio.create_task(self._aws_loop())
        asyncio.create_task(self._poll_loop())


# ── Config loading ────────────────────────────────────────────────────────────

def load_config() -> dict:
    config_path = Path(__file__).parent / "config.yaml"
    if not config_path.exists():
        raise SystemExit(
            f"\nconfig.yaml not found at {config_path}\n"
            "  cp config.yaml.example config.yaml\n"
            "  # then edit config.yaml with your SSH key path\n"
        )

    with open(config_path) as f:
        cfg = yaml.safe_load(f) or {}

    if not cfg.get("vsrx_public_ip"):
        terraform_dir = Path(__file__).parent.parent / "terraform"
        try:
            r = subprocess.run(
                ["terraform", "output", "-raw", "vsrx_mgmt_public_ip"],
                cwd=terraform_dir, capture_output=True, text=True, timeout=15,
            )
            ip = r.stdout.strip()
            if re.match(r"^\d+\.\d+\.\d+\.\d+$", ip):
                cfg["vsrx_public_ip"] = ip
                print(f"[config] auto-detected vsrx_public_ip = {ip}")
            else:
                raise SystemExit(
                    "vsrx_public_ip not set in config.yaml and terraform output failed.\n"
                    "Set vsrx_public_ip explicitly in config.yaml."
                )
        except FileNotFoundError:
            raise SystemExit("vsrx_public_ip not set in config.yaml and terraform not found.")

    key = Path(cfg.get("ssh_key_path", "")).expanduser()
    if not key.exists():
        raise SystemExit(f"SSH key not found: {key}\nSet ssh_key_path in config.yaml.")

    return cfg


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    cfg  = load_config()
    port = cfg.get("port", 8080)

    print("=" * 56)
    print("  vSRX Security Demo Dashboard")
    print("=" * 56)
    print(f"  vSRX:    {cfg['vsrx_public_ip']}")
    print(f"  Key:     {cfg['ssh_key_path']}")
    print(f"  Region:  {cfg.get('aws_region', 'ap-southeast-1')}")
    print(f"  Poll:    every {cfg.get('poll_interval_seconds', 15)}s  "
          f"(AWS every {cfg.get('aws_poll_interval_seconds', 30)}s)")
    print("-" * 56)
    print(f"  Open:    http://localhost:{port}")
    print("=" * 56)

    dashboard = Dashboard(cfg)
    app = dashboard.build_app()
    app.on_startup.append(dashboard.on_startup)

    webbrowser.open(f"http://localhost:{port}", new=2)
    web.run_app(app, host="0.0.0.0", port=port, print=None)


if __name__ == "__main__":
    main()
