#For OpenWRT based router

echo $(date)
target="10.9.0.1"
if ping -c 1 "$target" >/dev/null 2>&1; then
# Ping succeeded (exit status 0)
echo "Ping to $target succeeded."
# Execute command when ping succeeds
# Example command:
# command_when_ping_succeeds
else
# Ping failed (exit status non-zero)
echo "Ping to $target failed."
ifdown wg_srjp || true
sleep 20s && ifup wg_srjp
# Execute command when ping fails
# Example command:
# command_when_ping_fails
fi

#For regular linux PC
#!/bin/bash
echo $(date)
target="10.9.0.1"
if ping -c 1 "$target" >/dev/null 2>&1; then
# Ping succeeded (exit status 0)
echo "Ping to $target succeeded."
# Execute command when ping succeeds
# Example command:
# command_when_ping_succeeds
else
# Ping failed (exit status non-zero)
echo "Ping to $target failed."
wg-quick down srjp || true
sleep 20s && wg-quick up srjp
# Execute command when ping fails
# Example command:
# command_when_ping_fails
fi