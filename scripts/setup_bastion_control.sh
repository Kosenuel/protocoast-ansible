#!/usr/bin/env bash
set -euo pipefail

# setup_bastion_control.sh
#
# Interactive script to prepare a bastion host to act as the Ansible control node.
# Installs system packages, creates a Python virtualenv, installs Ansible, and
# optionally clones your repository and creates a dedicated SSH key for Ansible
# to use when connecting to internal cluster nodes.
#
# Usage: sudo ./setup_bastion_control.sh

SUDO=''
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO='sudo'
  else
    echo "This script requires root privileges. Re-run as root or install sudo." >&2
    exit 1
  fi
fi

echo "Preparing bastion as Ansible control node..."

read -r -p "Bastion user to configure (default: current user): " BASTION_USER
BASTION_USER=${BASTION_USER:-$(logname 2>/dev/null || echo $SUDO_USER || echo $USER)}
HOME_DIR=$(eval echo "~$BASTION_USER")

echo "Using user: $BASTION_USER (home: $HOME_DIR)"

read -r -p "Install system packages (python3, venv, pip, git, openssh)? [Y/n] " resp
resp=${resp:-Y}
if [[ "$resp" =~ ^[Yy] ]]; then
  # detect pkg manager
  if [ -f /etc/debian_version ]; then
    echo "Detected Debian/Ubuntu. Updating apt and installing packages..."
    $SUDO apt-get update
    $SUDO apt-get install -y python3 python3-venv python3-pip git openssh-client openssh-server ca-certificates build-essential
  elif [ -f /etc/redhat-release ] || [ -f /etc/centos-release ]; then
    echo "Detected RHEL/CentOS. Installing packages with yum/dnf..."
    if command -v dnf >/dev/null 2>&1; then
      $SUDO dnf install -y python3 python3-venv python3-pip git openssh-clients openssh-server gcc make
    else
      $SUDO yum install -y python3 python3-venv python3-pip git openssh-clients openssh-server gcc make
    fi
  else
    echo "Unknown distro. Please install python3, pip, git and openssh manually." >&2
  fi
fi

# Create python venv
VENV_DIR="$HOME_DIR/ansible-venv"
if [ ! -d "$VENV_DIR" ]; then
  echo "Creating Python venv at $VENV_DIR"
  $SUDO -u "$BASTION_USER" python3 -m venv "$VENV_DIR"
fi

echo "Activating venv and installing Ansible (as $BASTION_USER)..."
$SUDO -u "$BASTION_USER" bash -c "source '$VENV_DIR/bin/activate' && python -m pip install --upgrade pip && pip install ansible"

# Optional: clone repo
read -r -p "Do you want to git-clone a repository into the bastion (ansible working copy)? [y/N] " clone_resp
clone_resp=${clone_resp:-N}
if [[ "$clone_resp" =~ ^[Yy] ]]; then
  read -r -p "Repository URL (git clone URL): " REPO_URL
  if [ -z "$REPO_URL" ]; then
    echo "No repository URL provided, skipping clone."
  else
    TARGET_DIR="$HOME_DIR/ansible-repo"
    if [ -d "$TARGET_DIR/.git" ]; then
      echo "Repository already exists at $TARGET_DIR. Running git pull..."
      $SUDO -u "$BASTION_USER" git -C "$TARGET_DIR" pull
    else
      echo "Cloning $REPO_URL to $TARGET_DIR"
      $SUDO -u "$BASTION_USER" git clone "$REPO_URL" "$TARGET_DIR"
    fi
    echo "If your playbooks live in a subdirectory (e.g. ansible2), note the path: $TARGET_DIR"
  fi
fi

# Optional: create dedicated SSH key for Ansible (to connect from bastion to internal nodes)
read -r -p "Create a dedicated SSH keypair for Ansible on the bastion? [y/N] " key_resp
key_resp=${key_resp:-N}
if [[ "$key_resp" =~ ^[Yy] ]]; then
  SSH_DIR="$HOME_DIR/.ssh"
  $SUDO -u "$BASTION_USER" mkdir -p "$SSH_DIR"
  KEY_NAME="id_ansible"
  KEY_PATH="$SSH_DIR/$KEY_NAME"
  if [ -f "$KEY_PATH" ]; then
    echo "Key $KEY_PATH already exists. Skipping key generation."
  else
    echo "Generating key $KEY_PATH"
    $SUDO -u "$BASTION_USER" ssh-keygen -t rsa -b 4096 -f "$KEY_PATH" -N '' -C "ansible@$HOSTNAME"
    $SUDO chmod 600 "$KEY_PATH"
    $SUDO chmod 644 "$KEY_PATH.pub"
    echo "Public key created at $KEY_PATH.pub. Add this to internal nodes' authorized_keys or use it with your provisioning tool."
  fi
  echo "You can reference the key in playbooks as ~/.ssh/$KEY_NAME"
fi

echo
echo "Configuration summary for $BASTION_USER:" 
echo " - Python venv: $VENV_DIR"
if [[ "$clone_resp" =~ ^[Yy] ]] && [ -n "${TARGET_DIR-}" ]; then
  echo " - Repo cloned at: $TARGET_DIR"
fi
if [[ "$key_resp" =~ ^[Yy] ]]; then
  echo " - Ansible SSH key: $KEY_PATH (private) and $KEY_PATH.pub (public)"
fi

echo
echo "Next steps / recommendations:" 
cat <<'EOF'
- If you cloned the repository to the bastion, run your playbooks there using the venv:
    source ~/ansible-venv/bin/activate
    cd ~/ansible-repo/ansible2   # or wherever your playbooks are
    ansible-playbook -i inventory/mycluster/hosts.yaml playbooks/prepare.yml -u <node-user> --private-key ~/.ssh/id_ansible

- If you prefer to keep your private keys only on your workstation, configure sudoers/SSH agent or use ssh-copy-id from your workstation to add your public key to the bastion user.
- Remove any temporary keys from the bastion after you're finished if you created them here and do not need them.
EOF

echo "Bastion preparation complete."
