#!/bin/bash
USER=rhel

echo "Adding wheel" > /root/post-run.log
usermod -aG wheel rhel

echo "Setup build host" > /tmp/progress.log
chmod 666 /tmp/progress.log

# Set up libvirt for running VMs
systemctl enable --now libvirtd
sed -i 's/hosts:\s\+ files/& libvirt libvirt_guest/' /etc/nsswitch.conf

# Set up registry authentication
mkdir -p ~/.config/containers
cat <<EOF> ~/.config/containers/auth.json
{
    "auths": {
      "registry.redhat.io": {
        "auth": "${REGISTRY_PULL_TOKEN}"
      }
    }
  }
EOF

# Pull the needed images to minimize waiting during the lab
BOOTC_RHEL_VER=10.1
podman pull registry.redhat.io/rhel10/rhel-bootc:$BOOTC_RHEL_VER
podman pull registry.redhat.io/rhel10/bootc-image-builder:$BOOTC_RHEL_VER

# Generate SSH key for VM access
ssh-keygen -t ed25519 -f ~/.ssh/${GUID}key -N '' -C "Lab SSH Key"

# Create config.toml for bootc-image-builder
cat <<EOF> /root/config.toml
[[customizations.user]]
name = "core"
password = "redhat"
groups = ["wheel"]
key = "$(cat ~/.ssh/${GUID}key.pub)"
EOF

# Script that manages the bootc-vm SSH session tab
cat <<'SCRIPT'> /root/.wait_for_bootc_vm.sh
#!/bin/bash
echo "Waiting for VM 'bootc-vm' to be running..."
VM_NAME=bootc-vm
while true; do
    VM_STATE=$(virsh domstate "$VM_NAME" 2>/dev/null)
    if [[ "$VM_STATE" == "running" ]]; then
        break
    fi
    sleep 10
done
echo "Waiting for SSH to be available..."
while true; do
    if ping -c 1 -W 1 ${VM_NAME} &>/dev/null; then
        break
    fi
    sleep 5
done
ssh -i ~/.ssh/${GUID}key -o StrictHostKeyChecking=no core@${VM_NAME}
SCRIPT

chmod u+x /root/.wait_for_bootc_vm.sh

# Export environment variables for user sessions
echo "export GUID=${GUID}" >> /etc/profile.d/lab.sh
echo "export DOMAIN=${DOMAIN}" >> /etc/profile.d/lab.sh

echo "Build host setup complete" >> /tmp/progress.log
