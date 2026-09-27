# Safe VM Shutdown & Host Reboot Automation Guide

This guide explains how to set up a secure automation script to gracefully shut down a VirtualBox guest Linux VM via SSH and reboot the Windows host machine in a single action.

## 🔒 Security Architecture
To avoid storing plain-text passwords in the script, enabling insecure `root` SSH access, or allowing unrestricted passwordless `sudo` privileges, this solution implements a **Restricted SSH Key (Forced Command)** architecture.

* **No Plain-Text Passwords:** The script relies entirely on asymmetric SSH keys.
* **Isolated Sudo Privilege:** The VM user is granted passwordless `sudo` access *only* for the `poweroff` command.
* **Zero-Trust SSH Key:** Even if the private key on the host machine is compromised, it can *only* be used to trigger a shutdown. An attacker cannot open a shell, read files, or execute any other commands on the VM.

---

## 🛠️ Step-by-Step Setup Instructions

### Step 1: Create a Dedicated SSH Key on the Host
Open **Git Bash** on your Windows host and generate a unique SSH key pair specifically for this task:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_vm_shutdown -N ""
```

### Step 2: Configure Passwordless Shutdown on the VM
Log into your Linux virtual machine and open the sudoers configuration file safely using `visudo`:

```bash
sudo visudo
```

Add the following line to the very bottom of the file (replace `your_username` with your actual VM username):

```text
your_username ALL=(ALL) NOPASSWD: /usr/sbin/poweroff
```
> *Note: Depending on your Linux distribution, the path might be `/sbin/poweroff`. You can verify this on your VM by running `which poweroff`.*

### Step 3: Restrict the SSH Key on the VM
Open or create the `authorized_keys` file inside your VM:

```bash
nano ~/.ssh/authorized_keys
```

Get the content of your host's public key (`~/.ssh/id_ed25519_vm_shutdown.pub`). Paste it into the `authorized_keys` file, but prepend it with the security restrictions exactly like this:

```text
command="sudo poweroff",no-port-forwarding,no-x11-forwarding,no-agent-forwarding,no-pty ssh-ed25519 AAAAC3NzaC1l...[rest of your public key]
```

### Step 4: Add the Automation Script
Create a script named `safeboot.sh` on your host PC and paste the following English automation code:

```bash
#!/bin/bash

# 1. Configuration Settings
VM_USER="your_username"
VM_IP="127.0.0.1"          
VM_PORT="2222"             
VM_NAME="YOUR_VM_NAME"
# Path to the restricted private SSH key you created
KEY_PATH="\$HOME/.ssh/id_ed25519_vm_shutdown"

echo "Requesting a safe VM shutdown using the restricted SSH key..."

# Because the command is forced on the VM side via authorized_keys, 
# any command payload sent here (even empty strings "") will trigger "sudo poweroff".
ssh -i "\(KEY_PATH" -p \)VM_PORT \({VM_USER}@\){VM_IP} ""

echo "Waiting for the VM to power off completely..."
# Loop checks the VM status every 2 seconds until it is "powered off"
while true; do
    STATUS=\$(cmd //c VBoxManage showvminfo "\$VM_NAME" --machinereadable | grep "VMState=" | cut -d'"' -f2)
    
    if [ "\(STATUS" = "poweroff" ] \vert{}\vert{} [ -z "\)STATUS" ]; then
        echo "VM shutdown confirmed successfully."
        break
    fi
    
    echo "Shutdown in progress... (Current state: \$STATUS) Checking again in 2s..."
    sleep 2
done

echo "All clear! Rebooting the host PC now..."
sleep 1

# Triggers an immediate reboot of your Windows host PC
cmd //c shutdown /r /t 0
```

Make the script executable in Git Bash:
```bash
chmod +x safeboot.sh
```

---

## 🚀 Usage
Simply run the script from Git Bash whenever you need to safely reboot your system:
```bash
./safeboot.sh
```
The script will cleanly offload the VM state, wait for complete disk synchronization to avoid corruption, and then safely perform a Windows system reboot.
