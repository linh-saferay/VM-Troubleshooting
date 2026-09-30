# Disable sleep completely with mask (confirmed)
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# Enable again (not tested yet)
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target

# Verify with Ubuntu 24 (desktop) - not tested
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0

# turn off suspend by gdm (login screen) by editing "/etc/gdm3/greeter.dconf-defaults"
sleep-inactive-ac-type = 'nothing'
sleep-inactive-battery-type = 'nothing'
sudo systemctl restart gdm3
# then verify
sudo -u gdm env DCONF_PROFILE=gdm dbus-run-session \
  gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type
sudo -u gdm env DCONF_PROFILE=gdm dbus-run-session \
  gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type


  
