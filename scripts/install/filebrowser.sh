#!/usr/bin/env bash
#
# authors: liara userdocs
#
# GNU General Public License v3.0 or later
#
########
######## Variables Start
########
#
# Get our main user credentials to use when bootstrapping filebrowser.
username="$(cut -d: -f1 < /root/.master.info)"
password="$(cut -d: -f2 < /root/.master.info)"
#
# This will generate a random port for the script between the range 10001 to 32001 to use with applications.
app_port_http="$(shuf -i 10001-32001 -n 1)" && while [[ "$(ss -ln | grep -co ''"${app_port_http}"'')" -ge "1" ]]; do app_port_http="$(shuf -i 10001-32001 -n 1)"; done
#
########
######## Variables End
########
#
########
######## Application script starts.
########
#
# Create the required directories for this application.
mkdir -p "/home/${username}/bin"
mkdir -p "/home/${username}/.config/Filebrowser"
#
# Download and extract the files to the desired location.
echo_progress_start "Downloading and extracting source code"
wget -O "/home/${username}/filebrowser.tar.gz" "$(curl -sNL https://api.github.com/repos/filebrowser/filebrowser/releases/latest | grep -Po 'ht(.*)linux-amd64(.*)gz')" >> $log 2>&1
tar -xvzf "/home/${username}/filebrowser.tar.gz" --exclude LICENSE --exclude README.md -C "/home/${username}/bin" >> $log 2>&1
echo_progress_done
#
# Removes the archive as we no longer need it.
rm -f "/home/${username}/filebrowser.tar.gz" >> "$log" 2>&1
#
# Perform some bootstrapping commands on filebrowser to create the database settings we desire.
#
# Create a self signed cert in the config directory to use with filebrowser.
#shellcheck source=sources/functions/ssl
. /etc/swizzin/sources/functions/ssl
create_self_ssl ${username}

#
# This command initialise our database.
echo_progress_start "Initialising database and configuring Filebrowser"
"/home/${username}/bin/filebrowser" config init -d "/home/${username}/.config/Filebrowser/filebrowser.db" >> "$log" 2>&1
#
# These commands configure some options in the database.
"/home/${username}/bin/filebrowser" config set -t "/home/${username}/.ssl/${username}-self-signed.crt" -k "/home/${username}/.ssl/${username}-self-signed.key" -d "/home/${username}/.config/Filebrowser/filebrowser.db" >> "$log" 2>&1
"/home/${username}/bin/filebrowser" config set -a 0.0.0.0 -p "${app_port_http}" -l "/home/${username}/.config/Filebrowser/filebrowser.log" -d "/home/${username}/.config/Filebrowser/filebrowser.db" >> "$log" 2>&1
"/home/${username}/bin/filebrowser" users add "${username}" "${password}" --perm.admin -d "/home/${username}/.config/Filebrowser/filebrowser.db" >> "$log" 2>&1
#
# Set the permissions after we are finsished configuring filebrowser.
chown "${username}.${username}" -R "/home/${username}/bin" > /dev/null 2>&1
chown "${username}.${username}" -R "/home/${username}/.config" > /dev/null 2>&1
chmod 700 "/home/${username}/bin/filebrowser" > /dev/null 2>&1
echo_progress_done
#
# Create the service file that will start and stop filebrowser.
echo_progress_start "Installing systemd service"
cat > "/etc/systemd/system/filebrowser.service" <<- SERVICE
	[Unit]
	Description=filebrowser
	After=network.target

	[Service]
	User=${username}
	Group=${username}
	UMask=002

	Type=simple
	WorkingDirectory=/home/${username}
	ExecStart=/home/${username}/bin/filebrowser -d /home/${username}/.config/Filebrowser/filebrowser.db
	TimeoutStopSec=20
	KillMode=process
	Restart=always
	RestartSec=2

	[Install]
	WantedBy=multi-user.target
SERVICE
#
# Configure the nginx proxypass using positional parameters.
if [[ -f /install/.nginx.lock ]]; then
    echo_progress_start "Installing nginx config"
    bash "/usr/local/bin/swizzin/nginx/filebrowser.sh" "${app_port_http}"
    systemctl reload nginx
    echo_progress_done "Nginx config installed"
else
    echo_info "FileBrowser will run on port ${app_port_http}"
fi
#
# Start the filebrowser service.
systemctl daemon-reload -q
systemctl enable -q --now "filebrowser.service" 2>&1 | tee -a $log
echo_progress_done "Systemd service installed"
#
# This file is created after installation to prevent reinstalling. You will need to remove the app first which deletes this file.
touch "/install/.filebrowser.lock"
#
# A helpful echo to the terminal.
echo_success "FileBrowser installed"
echo_warn "Make sure to use your swizzin credentials when logging in"
#
exit
