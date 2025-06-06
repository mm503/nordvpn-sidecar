#!/bin/bash

# Global flag to track shutdown state
SHUTDOWN=false

do_fail() {
  echo "> Error: $1"
  echo "> Please check the log for more detail:"
  cat /var/log/nordvpn/daemon.log 2>/dev/null || echo "Log not available"
  exit 1
}

cleanup() {
    echo "> Received shutdown signal, cleaning up..."
    SHUTDOWN=true

    echo "> Disconnecting from NordVPN..."
    nordvpn disconnect || true

    echo "> Logging out from NordVPN..."
    nordvpn logout --persist-token || true

    echo "> Stopping NordVPN daemon..."
    /etc/init.d/nordvpn stop || true

    echo "> Cleanup completed"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT SIGQUIT

# check if we have NET_ADMIN capability
if ! capsh --print | grep -q cap_net_admin; then
    echo "> Error: NET_ADMIN capability required"
    exit 1
fi

# Check if we have a token
if [[ -z "${TOKEN}" ]]; then
    echo "> Error: TOKEN environment variable required"
    exit 1
fi

echo "> Starting NordVPN daemon"
if ! /etc/init.d/nordvpn start; then
  do_fail "Failed to start NordVPN daemon."
fi

# Wait for daemon to be ready
sleep 2

echo "> Logging in to NordVPN"
SLEEP=2
for i in {1..3}; do
    if nordvpn login --token "${TOKEN}"; then
        echo " - Login successful"
        break
    fi
    [[ $i -eq 3 ]] && { do_fail "Login failed after 3 attempts"; }
    echo " - Login attempt $i failed, retrying in ${SLEEP}s..."
    sleep $SLEEP
    let SLEEP=$((SLEEP * 2))
done

echo "> Connecting to NordVPN"
if nordvpn connect; then
  echo " - Successfully connected to NordVPN. Status:"
  nordvpn status
else
  do_fail "Failed to connect to NordVPN. Please check your connection settings."
fi

echo "> Monitoring connection (PID: $$)"

# Maintain connection and exit if connection drops
while [[ "$SHUTDOWN" == "false" ]]; do
  # Check if we received a shutdown signal
  if [[ "$SHUTDOWN" == "true" ]]; then
    break
  fi

  # Check connection status
  if ! nordvpn status | grep -q "Connected"; then
    echo "> Connection lost. Reconnecting..."
    if nordvpn connect; then
      echo " - Reconnected to NordVPN. Status:"
      nordvpn status
    else
      echo "> Failed to reconnect. Will retry in 30 seconds..."
      sleep 30
      continue
    fi
  fi

  # Sleep with signal-aware mechanism
  for i in {1..10}; do
    [[ "$SHUTDOWN" == "true" ]] && break
    sleep 1
  done
done

echo "> Main loop exited"
cleanup
