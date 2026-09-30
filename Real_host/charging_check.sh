# Doc truc tiep tu kernel, bo qua upowerd
cat /sys/class/power_supply/BAT*/status
cat /sys/class/power_supply/BAT*/capacity
cat /sys/class/power_supply/BAT*/energy_now 2>/dev/null || cat /sys/class/power_supply/BAT*/charge_now
cat /sys/class/power_supply/AC*/online 2>/dev/null || cat /sys/class/power_supply/A*/online

# So sanh voi upower cache
cat /var/lib/upower/history-charge-*.dat | tail -5
