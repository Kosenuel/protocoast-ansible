#!/usr/bin/env python3
"""Generate a Kubespray-compatible inventory (YAML) from Terraform/OpenTofu JSON outputs.

Usage:
  python gen_inventory_from_tf.py --outputs outputs.json --user ubuntu --key ~/.ssh/id_rsa --out ../inventory/mycluster/hosts.yaml

The script looks for common output names produced by the modules in this repo, for example:
- control_plane_names / control_plane_ips
- worker_names / worker_ips
- bastion_public_ip / bastion_private_ip

It is defensive: if names are missing it will synthesize hostnames, and will warn about missing values.
"""
import argparse
import json
import os
import sys
from collections import defaultdict

try:
    import yaml
except Exception:
    print("PyYAML is required: pip install pyyaml")
    sys.exit(1)


def load_outputs(path):
    with open(path, 'r') as f:
        data = json.load(f)
    # Terraform/OpenTofu outputs: {"key": {"value": ...}, ...}
    outputs = {}
    for k, v in data.items():
        if isinstance(v, dict) and 'value' in v:
            outputs[k] = v['value']
        else:
            outputs[k] = v
    return outputs


def pick(outputs, *candidates):
    for c in candidates:
        if c in outputs:
            return outputs[c]
    return None


def build_hosts(outputs, ssh_user, ssh_key):
    hosts = {}
    warnings = []

    # Control plane
    cp_names = pick(outputs, 'control_plane_names', 'control_plane_node_names', 'cp_names')
    cp_ips = pick(outputs, 'control_plane_ips', 'control_plane_private_ips', 'cp_ips', 'control_plane_private_ips')
    if cp_ips is None and 'control_plane_count' in outputs:
        warnings.append('control_plane_ips missing but control_plane_count present')

    # Workers
    worker_names = pick(outputs, 'worker_names', 'worker_node_names', 'worker_node_names')
    worker_ips = pick(outputs, 'worker_ips', 'worker_private_ips', 'worker_ips')

    # Bastion (optional)
    bastion_priv = pick(outputs, 'bastion_private_ip', 'bastion_private_ips')
    bastion_pub = pick(outputs, 'bastion_public_ip', 'bastion_public_ips')

    def add_group(names, ips, prefix, group_hosts):
        if names is None and ips is None:
            return
        count = max(len(names) if names else 0, len(ips) if ips else 0)
        for i in range(count):
            name = (names[i] if names and i < len(names) else f"{prefix}-{i+1}")
            ip = ips[i] if ips and i < len(ips) else None
            if ip is None:
                warnings.append(f'Missing IP for host {name}')
                continue
            host = {
                'ansible_host': ip,
                'ip': ip,
                'ansible_user': ssh_user,
                'ansible_ssh_private_key_file': ssh_key,
            }
            # access_ip left empty unless public IP mapping available
            group_hosts[name] = host

    cp_hosts = {}
    add_group(cp_names, cp_ips, 'k8s-cp', cp_hosts)
    worker_hosts = {}
    add_group(worker_names, worker_ips, 'k8s-worker', worker_hosts)

    if bastion_priv:
        # bastion might be single value or list
        if isinstance(bastion_priv, list):
            for idx, ip in enumerate(bastion_priv, 1):
                hosts[f'bastion-{idx}'] = {
                    'ansible_host': ip,
                    'ip': ip,
                    'access_ip': (bastion_pub[idx-1] if bastion_pub and idx-1 < len(bastion_pub) else None),
                    'ansible_user': ssh_user,
                    'ansible_ssh_private_key_file': ssh_key,
                }
        else:
            hosts['bastion-1'] = {
                'ansible_host': bastion_priv,
                'ip': bastion_priv,
                'access_ip': bastion_pub if isinstance(bastion_pub, str) else (bastion_pub[0] if bastion_pub else None),
                'ansible_user': ssh_user,
                'ansible_ssh_private_key_file': ssh_key,
            }

    # Merge cp and worker hosts into hosts dict
    hosts.update(cp_hosts)
    hosts.update(worker_hosts)

    groups = defaultdict(dict)
    if cp_hosts:
        groups['kube_control_plane'] = {'hosts': {k: {} for k in cp_hosts}}
    if worker_hosts:
        groups['kube_node'] = {'hosts': {k: {} for k in worker_hosts}}
    if cp_hosts:
        groups['etcd'] = {'hosts': {k: {} for k in cp_hosts}}

    # Always add k8s_cluster children
    groups['k8s_cluster'] = {'children': {}}
    if 'kube_control_plane' in groups:
        groups['k8s_cluster']['children']['kube_control_plane'] = {}
    if 'kube_node' in groups:
        groups['k8s_cluster']['children']['kube_node'] = {}

    return hosts, groups, warnings


def write_inventory(path, hosts, groups):
    inv = {'all': {'hosts': hosts, 'children': {}}}
    inv['all']['children'] = groups
    dirpath = os.path.dirname(path)
    os.makedirs(dirpath, exist_ok=True)
    with open(path, 'w') as f:
        yaml.safe_dump(inv, f, sort_keys=False)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--outputs', '-o', required=True, help='Path to terraform/tofu outputs JSON (terraform output -json)')
    p.add_argument('--user', '-u', default='ubuntu', help='SSH user for Ansible')
    p.add_argument('--key', '-k', default='~/.ssh/id_rsa', help='Path to private SSH key for Ansible')
    p.add_argument('--out', default='../inventory/mycluster/hosts.yaml', help='Output inventory YAML path')
    args = p.parse_args()

    outputs = load_outputs(args.outputs)
    hosts, groups, warnings = build_hosts(outputs, args.user, os.path.expanduser(args.key))
    if not hosts:
        print('No hosts discovered in outputs. Check your outputs JSON for control_plane/_worker/bastion keys.')
        sys.exit(2)
    write_inventory(os.path.abspath(args.out), hosts, groups)
    print(f'Inventory written to {os.path.abspath(args.out)}')
    if warnings:
        print('\nWarnings:')
        for w in warnings:
            print('-', w)


if __name__ == '__main__':
    main()
