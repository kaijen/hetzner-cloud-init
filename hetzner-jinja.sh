#!/bin/bash
set -euo pipefail

# Hetzner Cloud-Init equivalent bash script
# Generated from hetzner-jinja.yml.jinja

# Host configuration
HOST_NAME="humboldt"
HOST_FQDN="humboldt.tim.jendrian.de"

# User definitions
declare -A USERS
USERS[kai]="github:kaijen:"
USERS[tim]="keys:ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXOTDsMRjwRmBtERuUg5nxdl7pfngAwWqR3r1shpfvr,ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFwfCCMix8lC0Cha1tbr7fPt9bRiwwSG30DUsuzb9nyr:"
USERS[ansible]="keys:ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOTH7wfLQu4O0RBAukHj4XKCRw9xsi9RKitieEZuADwT:ansible"

# Firewall ports
FIREWALL_PORTS=("22/tcp:SSH" "80/tcp:HTTP" "443/tcp:HTTPS")

echo "Starting system configuration..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Set timezone
timedatectl set-timezone Europe/Berlin

# Set hostname
hostnamectl set-hostname "$HOST_NAME"
echo "127.0.1.1 $HOST_FQDN $HOST_NAME" >> /etc/hosts

# Set locale
locale-gen en_US.UTF-8
localectl set-locale LANG=en_US.UTF-8

# Update packages
apt-get update
apt-get upgrade -y

# Install packages
apt-get install -y \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libffi-dev \
    liblzma-dev \
    tk-dev \
    uuid-dev \
    xz-utils \
    fail2ban \
    ufw \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    chrony

# Configure unattended upgrades
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Package-Blacklist {
};
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# Write configuration files
cat > /etc/ssh/sshd_config.d/hardening.conf << 'EOF'
# SSH-Härtung
Protocol 2
PermitRootLogin no
MaxAuthTries 3
MaxSessions 5
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Banner /etc/issue.net
ClientAliveInterval 300
ClientAliveCountMax 2
PermitEmptyPasswords no
AllowTcpForwarding no
AllowAgentForwarding no
LoginGraceTime 30s
LogLevel VERBOSE
EOF

cat > /etc/issue.net << 'EOF'
***************************************************************************
*                            AUTHORIZED USE ONLY                          *
* Unauthorized access is strictly prohibited and will be monitored        *
***************************************************************************
EOF

cat > /etc/logrotate.conf << 'EOF'
# Globale Logrotate-Konfiguration
weekly
rotate 4
create
compress
dateext
include /etc/logrotate.d
EOF

cat > /etc/sysctl.d/99-custom.conf << 'EOF'
# Erhöht die Netzwerkperformance
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# Verbessert die Speichernutzung
vm.swappiness = 10
vm.vfs_cache_pressure = 50

# Basis-Sicherheitseinstellungen
net.ipv4.conf.all.rp_filter = 1
kernel.randomize_va_space = 2
EOF

cat > /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled = true
maxretry = 5
findtime = 600
bantime = 7200
EOF

# Configure NTP (chrony)
cat > /etc/chrony/chrony.conf << 'EOF'
server 0.de.pool.ntp.org iburst
server 1.de.pool.ntp.org iburst
server 2.de.pool.ntp.org iburst

driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
EOF

# Apply sysctl settings
sysctl -p /etc/sysctl.d/99-custom.conf

# Restart SSH service
systemctl restart ssh

# Configure firewall
for port_rule in "${FIREWALL_PORTS[@]}"; do
    IFS=':' read -ra PORT_CONFIG <<< "$port_rule"
    PORT="${PORT_CONFIG[0]}"
    COMMENT="${PORT_CONFIG[1]}"
    ufw allow "$PORT" comment "$COMMENT"
done

ufw default deny incoming
ufw default allow outgoing
echo "y" | ufw enable

# Install Docker
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin
systemctl enable docker
systemctl start docker

# Create users
for username in "${!USERS[@]}"; do
    echo "Creating user: $username"

    # Create user
    useradd -m -s /bin/bash "$username"
    usermod -aG users,docker "$username"

    # Set sudo privileges
    echo "$username ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$username"

    # Parse user configuration
    IFS=':' read -ra USER_CONFIG <<< "${USERS[$username]}"
    SSH_METHOD="${USER_CONFIG[0]}"
    SSH_VALUE="${USER_CONFIG[1]}"

    # Configure SSH
    mkdir -p "/home/$username/.ssh"
    chown "$username:$username" "/home/$username/.ssh"
    chmod 700 "/home/$username/.ssh"

    if [[ "$SSH_METHOD" == "github" ]]; then
        # Import GitHub SSH keys
        sudo -u "$username" ssh-import-id "gh:$SSH_VALUE"
    elif [[ "$SSH_METHOD" == "keys" ]]; then
        # Add SSH keys directly
        IFS=',' read -ra KEYS <<< "$SSH_VALUE"
        for key in "${KEYS[@]}"; do
            echo "$key" >> "/home/$username/.ssh/authorized_keys"
        done
        chown "$username:$username" "/home/$username/.ssh/authorized_keys"
        chmod 600 "/home/$username/.ssh/authorized_keys"
    fi
done



# Setup Python environment for users
for username in "${!USERS[@]}"; do
    echo "Setting up Python environment for user: $username"

    # Parse user configuration for Python packages
    IFS=':' read -ra USER_CONFIG <<< "${USERS[$username]}"
    PYTHON_PACKAGES="${USER_CONFIG[2]:-}"

    # Install pyenv
    su - "$username" -c 'curl https://pyenv.run | bash'

    # Configure bashrc
    su - "$username" -c 'echo "export PATH=\"\$HOME/.pyenv/bin:\$PATH\"" >> ~/.bashrc'
    su - "$username" -c 'echo "eval \"\$(pyenv init --path)\"" >> ~/.bashrc'
    su - "$username" -c 'echo "eval \"\$(pyenv init -)\"" >> ~/.bashrc'
    su - "$username" -c 'echo "eval \"\$(pyenv virtualenv-init -)\"" >> ~/.bashrc'

    # Install Python 3.13
    su - "$username" -c '~/.pyenv/bin/pyenv install 3.13'
    su - "$username" -c '~/.pyenv/bin/pyenv global 3.13'
    su - "$username" -c '~/.pyenv/bin/pyenv exec pip install --upgrade pip'

    # Install Python packages if specified
    if [[ -n "$PYTHON_PACKAGES" && "$PYTHON_PACKAGES" != "" ]]; then
        IFS=',' read -ra PACKAGES <<< "$PYTHON_PACKAGES"
        for package in "${PACKAGES[@]}"; do
            [[ -n "$package" ]] && su - "$username" -c "~/.pyenv/bin/pyenv exec pip install $package"
        done
    fi
done

# Start services
systemctl enable fail2ban
systemctl start fail2ban
systemctl enable chrony
systemctl start chrony

# Enable auto-reboot if required after package updates
if dpkg -l | grep -q linux-image; then
    echo "Packages updated. Reboot may be required."
fi

echo "System configuration completed successfully!"
UPTIME=$(cat /proc/uptime | cut -d' ' -f1)
echo "The system is finally up, after $UPTIME seconds"