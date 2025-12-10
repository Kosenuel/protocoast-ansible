# Ansible2  Kubespray deployment wrapper

Overview
--------
This directory contains a small Ansible wrapper around Kubespray to deploy a Kubernetes
cluster. The wrapper provides two main playbooks:

- `playbooks/prepare.yml`: prepares target hosts (installs Python, disables swap, sets
  hostnames, installs packages required by Ansible/Kubespray).
- `playbooks/kubespray-wrapper.yml`: clones (or updates) the Kubespray repository,
  generates a Kubespray-compatible inventory from `inventory/mycluster/hosts.yaml`,
  installs any control-machine dependencies, then runs Kubespray's `cluster.yml` to
  provision the Kubernetes cluster.

Files and purpose
-----------------
- `inventory/mycluster/hosts.yaml`  Kubespray-compatible inventory (YAML). Fill in
  real host IPs and SSH settings here.
- `inventory/mycluster/group_vars/`  group variable files (common Kubespray vars,
  network plugin choice, Kubernetes version, etc.).
- `playbooks/prepare.yml`  ensures remote hosts have the minimal prerequisites for
  Ansible and Kubespray.
- `playbooks/kubespray-wrapper.yml`  orchestrates cloning Kubespray and running the
  Kubespray playbook with the generated inventory.
- `ansible.cfg`  local Ansible configuration used when running the playbooks.

Inventory notes
---------------
Edit `inventory/mycluster/hosts.yaml` and ensure the following are set for each host/group as needed:

- `ansible_host` / `ip` / `access_ip`: IP address or hostname used to reach the host.
- `ansible_user`: the SSH user Ansible should use to login (must have `sudo` privileges).
- `ansible_ssh_private_key_file`: path to the private key on the machine running the playbooks,
  or pass `--private-key` on the `ansible-playbook` command line.

Group vars (under `group_vars/`) contain Kubespray-specific settings such as `kube_version`,
`kube_network_plugin`, and `kubespray_branch`. Review and adjust them for your environment.

Prerequisites
-------------
Local (controller machine where you run the playbooks):

- Python 3.8+ and `venv` (recommended to run Ansible in a virtual environment).
- `pip` and `ansible` installed (the wrapper expects Ansible available on the controller).
- SSH private key with passwordless access to target nodes, and the public key present in
  the target user's `~/.ssh/authorized_keys`.

Remote (target hosts):

- Python (2.7 or 3.x) available for Ansible modules, or the `prepare.yml` playbook will
  attempt to install it.
- `sudo` privileges for `ansible_user`.
- Network connectivity between control-plane and worker nodes for the Kubernetes overlay
  network and control-plane traffic.

Quick start (PowerShell)
------------------------
1. Create and activate a Python virtualenv, then install Ansible:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install --upgrade pip
pip install ansible
```

2. Test SSH/Ansible connectivity (replace user and key path):

```powershell
ansible -i ansible2/inventory/mycluster/hosts.yaml all -m ping -u <ssh_user> --private-key C:\path\to\key -vvvv
```

3. Run the preparation playbook (installs Python and common packages remotely):

```powershell
ansible-playbook -i ansible2/inventory/mycluster/hosts.yaml ansible2/playbooks/prepare.yml -u <ssh_user> --private-key C:\path\to\key
```

4. Run the Kubespray wrapper to deploy Kubernetes:

```powershell
ansible-playbook -i ansible2/inventory/mycluster/hosts.yaml ansible2/playbooks/kubespray-wrapper.yml -u <ssh_user> --private-key C:\path\to\key
```

Notes and troubleshooting
------------------------
- If Ansible reports missing Python on the remote host, run the `prepare.yml` playbook or
  install Python manually on the node (the `prepare` playbook is intended to handle this).
- Use `-v`/`-vvv` on `ansible-playbook` for more verbose logs when debugging failures.
- The wrapper clones Kubespray by default; ensure outbound access to the Git host (e.g. GitHub)
  from the machine running the wrapper.
- After deployment, obtain the generated `kubeconfig` (the wrapper or Kubespray output will
  indicate where it's placed) and verify cluster health:

```powershell
kubectl --kubeconfig C:\path\to\kubeconfig get nodes
kubectl --kubeconfig C:\path\to\kubeconfig get pods -A
```

Where to go next
----------------
- If you want, I can: review your `inventory/mycluster/hosts.yaml` and `group_vars` and
  give exact edits; run the connectivity ping from your controller and report results; or
  run the playbooks and help troubleshoot any failures. Tell me which you'd like.
