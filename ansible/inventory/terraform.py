#!/usr/bin/env python3
"""
Dynamic Ansible inventory built from Terraform infrastructure output.

Usage:
  ansible-inventory -i ansible/inventory/terraform.py --list
  ansible-inventory -i ansible/inventory/terraform.py --host vault-1
"""

import json
import subprocess
import sys
from pathlib import Path

INFRA_DIR = Path(__file__).resolve().parents[2] / "terraform" / "infra"


def terraform_output():
    result = subprocess.run(
        ["terraform", f"-chdir={INFRA_DIR}", "output", "-json"],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


def build_inventory(output):
    node_ipv4 = output.get("node_ipv4", {}).get("value", {})
    node_names = output.get("node_names", {}).get("value", [])

    hosts = {}
    for name in node_names:
        ip = node_ipv4.get(name)
        if ip:
            hosts[name] = {"ansible_host": ip}

    return {
        "vault": {
            "hosts": list(hosts.keys()),
            "vars": {
                "ansible_user": "ubuntu",
                "ansible_ssh_private_key_file": "~/.ssh/id_ed25519",
                "ansible_ssh_common_args": "-o StrictHostKeyChecking=no",
                "ansible_become": True,
                "ansible_become_method": "sudo",
            },
        },
        "_meta": {"hostvars": hosts},
    }


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--host":
        # Per-host vars are embedded in _meta; return empty dict
        print(json.dumps({}))
        return

    try:
        output = terraform_output()
    except subprocess.CalledProcessError as exc:
        sys.exit(f"terraform output failed: {exc.stderr.strip()}")

    print(json.dumps(build_inventory(output), indent=2))


if __name__ == "__main__":
    main()
