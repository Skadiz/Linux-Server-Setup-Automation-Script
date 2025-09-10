# Linux Server Setup Automation Script

A Bash script that automates **initial server hardening and configuration** on Ubuntu, Debian, Fedora, AlmaLinux and Rocky Linux.  
Perfect for quickly bootstrapping a new server with secure defaults.

---

##  Features

- ✅ System update & base tools installation (`curl`, `git`, `vim`, `htop`, etc.)
- ✅ Timezone configuration
- ✅ New user creation with **sudo privileges**
- ✅ SSH hardening
  - disable root login
  - disable password authentication (optional)
  - enable public key authentication
- ✅ Automatic **SSH key setup** for the new user
- ✅ **Firewall** configuration
  - UFW (Debian/Ubuntu) or firewalld (RHEL/Fedora/AlmaLinux)
  - allows only ports 22, 80, 443 by default
- ✅ **fail2ban** integration (protection against brute-force SSH attacks)
- ✅ Optional unattended security updates (Debian/Ubuntu)
- ✅ Custom MOTD banner

---

## Installation

Clone the repository and enter the project directory:

```bash
git clone https://github.com/Skadiz/linux-server-setup-automation.git
cd linux-server-setup-automation
chmod +x bootstrap-server.sh
⚙️ Usage
Example:

bash
sudo ./bootstrap-server.sh \
  --username katto \
  --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICsQlPmByxcccW+r//KgdExqc6aDedLzhQjnYpjz0KSS kurochkaseva@gmail.com" \
  --ufw-ports "22,80,443" \
  --timezone "Europe/Warsaw" \
  --no-password-login
Parameters:
--username — name of the user to create/grant sudo

--ssh-key — public SSH key to add to authorized_keys

--ufw-ports — comma-separated ports to allow in firewall (default: 22)

--timezone — system timezone (default: UTC)

--no-password-login — disables SSH password authentication (key only)

🧪 Example Run
After running the script:

bash
whoami
# katto

sudo ufw status
# Only ports 22, 80, 443 are allowed

sudo fail2ban-client status sshd
# Jail is running, brute-force protection active

ssh katto@localhost
# logs in with SSH key only
MOTD banner:

pgsql
Welcome! This server is managed by bootstrap-server.sh
- SSH root login: disabled
- Check: sudo systemctl status fail2ban
- Firewall: ufw/firewalld enabled
🛠️ Tested On
✅ Ubuntu 22.04 LTS (WSL2 & cloud VPS)

✅ Debian 12

✅ Fedora 39

✅ AlmaLinux 9
