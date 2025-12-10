<#!
NAME
    copy_ssh_to_bastion.ps1

SYNOPSIS
    Interactive helper to copy your SSH public key to a bastion host and
    optionally copy a private key there for Ansible use.

DESCRIPTION
    This script appends your public key to the bastion user's
    `~/.ssh/authorized_keys` and ensures correct permissions. Optionally it
    can copy a private key file to the bastion (e.g. for use when the bastion
    must SSH into internal nodes). Copying private keys to remote hosts is a
    security risk — use with care.

USAGE
    Run from PowerShell on your controller machine:

    .\ansible2\scripts\copy_ssh_to_bastion.ps1

    The script will prompt for bastion host, bastion user, key paths and
    whether to copy the private key.

NOTES
    Requires `ssh` and `scp` in PATH (OpenSSH client). The script uses the
    public key derived from a private key path you specify (default
    `%USERPROFILE%\.ssh\id_rsa`).
#>

param()

function Fail($msg) {
    Write-Error $msg
    exit 1
}

# check for ssh and scp
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Fail "`ssh` not found in PATH. Install OpenSSH client or add ssh to PATH."
}
if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
    Fail "`scp` not found in PATH. Install OpenSSH client or add scp to PATH."
}

Write-Host "This script will copy your SSH public key to the bastion host's authorized_keys." -ForegroundColor Cyan

$defaultPriv = "$env:USERPROFILE\.ssh\id_rsa"
if (-not (Test-Path $defaultPriv)) {
    $defaultPriv = "$env:USERPROFILE\.ssh\id_ed25519"
}

$privKeyPath = Read-Host "Path to your private key (press Enter for '$defaultPriv')"
if ([string]::IsNullOrWhiteSpace($privKeyPath)) { $privKeyPath = $defaultPriv }
if (-not (Test-Path $privKeyPath)) { Fail "Private key not found at: $privKeyPath" }

$pubKeyPath = "$privKeyPath.pub"
if (-not (Test-Path $pubKeyPath)) {
    Fail "Public key file not found. Expected: $pubKeyPath`nIf you only have a private key, run `ssh-keygen -y -f <private>` to generate the public key.`"
}

$bastionHost = Read-Host "Bastion host (IP or hostname)"
if ([string]::IsNullOrWhiteSpace($bastionHost)) { Fail "Bastion host is required." }

$defaultUser = $env:USERNAME
$bastionUser = Read-Host "Bastion SSH user (press Enter for '$defaultUser')"
if ([string]::IsNullOrWhiteSpace($bastionUser)) { $bastionUser = $defaultUser }

$target = "$bastionUser@$bastionHost"

Write-Host "Using public key: $pubKeyPath" -ForegroundColor Green
Write-Host "Target bastion: $target" -ForegroundColor Green

$confirm = Read-Host "Append public key to $target:~/.ssh/authorized_keys? (y/N)"
if ($confirm.ToLower() -ne 'y') { Write-Host "Aborted by user."; exit 0 }

$pubKey = Get-Content -Raw -Path $pubKeyPath
# escape single quotes for safe echo in remote shell
$escaped = $pubKey -replace "'", "'\"'\"'"

$remoteCmd = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$escaped' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

Write-Host "Appending public key to remote authorized_keys..." -NoNewline
$sshExit = & ssh $target $remoteCmd; $ec = $LASTEXITCODE
if ($ec -ne 0) { Write-Host " failed" -ForegroundColor Red; Fail "ssh command failed with exit code $ec" }
Write-Host " done" -ForegroundColor Green

$copyPriv = Read-Host "Do you also want to copy the private key to the bastion (for Ansible use)? This copies a sensitive file — only do this if you understand the risk. (y/N)"
if ($copyPriv.ToLower() -eq 'y') {
    $remoteName = Read-Host "Remote filename to create under ~/.ssh (e.g. id_ansible) (press Enter for 'id_ansible')"
    if ([string]::IsNullOrWhiteSpace($remoteName)) { $remoteName = 'id_ansible' }

    Write-Host "Copying private key to $target:~/.ssh/$remoteName ..." -NoNewline
    & scp $privKeyPath "$target:~/.ssh/$remoteName"
    $ec = $LASTEXITCODE
    if ($ec -ne 0) { Write-Host " failed" -ForegroundColor Red; Fail "scp failed with exit code $ec" }

    $sshChmodCmd = "chmod 600 ~/.ssh/$remoteName"
    & ssh $target $sshChmodCmd; $ec = $LASTEXITCODE
    if ($ec -ne 0) { Write-Host " failed" -ForegroundColor Red; Fail "ssh chmod failed with exit code $ec" }
    Write-Host " done" -ForegroundColor Green

    Write-Host "Private key copied. Ensure the bastion user and Ansible playbooks reference ~/.ssh/$remoteName as needed." -ForegroundColor Yellow
}

Write-Host "All done. You can now SSH to the bastion with your key or run Ansible using the bastion as jump host." -ForegroundColor Cyan
