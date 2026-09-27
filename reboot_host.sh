#!/bin/bash
# Original code by Gemini (Free plan) Not tested at all
# 1. Configuration Settings
VM_USER="your_username"
VM_IP="127.0.0.1"          
VM_PORT="2222"             
VM_NAME="YOUR_VM_NAME"
# Path to the restricted private SSH key you created
KEY_PATH="$HOME/.ssh/id_ed25519_vm_shutdown"

echo "Requesting a safe VM shutdown using the restricted SSH key..."

# Because the command is forced on the VM side via authorized_keys, 
# any command payload sent here (even empty strings "") will trigger "sudo poweroff".
ssh -i "$KEY_PATH" -p $VM_PORT ${VM_USER}@${VM_IP} ""

echo "Waiting for the VM to power off completely..."
# Loop checks the VM status every 2 seconds until it is "powered off"
while true; do
    STATUS=$(cmd //c VBoxManage showvminfo "$VM_NAME" --machinereadable | grep "VMState=" | cut -d'"' -f2)
    
    if [ "$STATUS" = "poweroff" ] || [ -z "$STATUS" ]; then
        echo "VM shutdown confirmed successfully."
        break
    fi
    
    echo "Shutdown in progress... (Current state: $STATUS) Checking again in 2s..."
    sleep 2
done

echo "All clear! Rebooting the host PC now..."
sleep 1

# Triggers an immediate reboot of your Windows host PC
cmd //c shutdown /r /t 0
