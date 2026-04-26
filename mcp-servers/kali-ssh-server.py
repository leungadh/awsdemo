# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp>=1.0.0", "paramiko>=3.0.0"]
# ///
"""MCP server: run commands on Kali via SSH."""

import asyncio
import subprocess
import sys
from mcp.server.fastmcp import FastMCP

KALI_HOST = "18.142.222.240"
KALI_USER = "ubuntu"
KALI_KEY  = "/Users/andy/.ssh/awsdemo.pem"

mcp = FastMCP("kali-ssh")


@mcp.tool()
def run_on_kali(command: str) -> str:
    """Run a shell command on the Kali Linux attacker VM and return its output."""
    result = subprocess.run(
        [
            "ssh",
            "-i", KALI_KEY,
            "-o", "StrictHostKeyChecking=no",
            "-o", "ConnectTimeout=10",
            f"{KALI_USER}@{KALI_HOST}",
            command,
        ],
        capture_output=True,
        text=True,
        timeout=60,
    )
    output = result.stdout
    if result.returncode != 0 and result.stderr:
        output += f"\n[stderr]\n{result.stderr}"
    return output or "(no output)"


@mcp.tool()
def upload_to_kali(local_path: str, remote_path: str) -> str:
    """Copy a local file to the Kali VM using scp."""
    result = subprocess.run(
        [
            "scp",
            "-i", KALI_KEY,
            "-o", "StrictHostKeyChecking=no",
            local_path,
            f"{KALI_USER}@{KALI_HOST}:{remote_path}",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode == 0:
        return f"Uploaded {local_path} → {KALI_USER}@{KALI_HOST}:{remote_path}"
    return f"scp failed (exit {result.returncode}):\n{result.stderr}"


if __name__ == "__main__":
    mcp.run(transport="stdio")
