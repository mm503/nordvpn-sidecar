#!/bin/bash

# Environment variable defaults
MAX_RECONNECT_ATTEMPTS="${MAX_RECONNECT_ATTEMPTS:-5}"
RECONNECT_INTERVAL="${RECONNECT_INTERVAL:-30}"
NORDVPN_KILLSWITCH="${NORDVPN_KILLSWITCH:-on}"

# Global flags
SHUTDOWN=false
RECONNECT_COUNT=0

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

# Check if we have NET_ADMIN capability
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

# Configure kill switch
echo "> Configuring kill switch: ${NORDVPN_KILLSWITCH}"
if ! nordvpn set killswitch "${NORDVPN_KILLSWITCH}"; then
    echo " - Warning: Failed to configure kill switch"
fi

# Configure Kubernetes and local subnets
if [[ -n "${ALLOW_SUBNETS}" ]]; then
  echo "> Configuring Kubernetes and local subnets"
  # Subnets are provided as a comma-separated list
  IFS=',' read -r -a SUBNETS <<< "${ALLOW_SUBNETS}"
  for subnet in "${SUBNETS[@]}"; do
    if ! nordvpn allowlist add subnet "$subnet"; then
      do_fail "Failed to whitelist subnet: $subnet"
    fi
    echo " - Whitelisted subnet: $subnet"
  done
else
  echo "> No subnets to whitelist. Skipping configuration."
fi

connect_vpn() {
    local connect_cmd="nordvpn connect"
    local fallback_attempted=false

    # Add country if specified
    if [[ -n "${NORDVPN_COUNTRY}" ]]; then
        connect_cmd+=" \"${NORDVPN_COUNTRY}\""

        # Add city if specified
        if [[ -n "${NORDVPN_CITY}" ]]; then
            connect_cmd+=" \"${NORDVPN_CITY}\""
        fi
    fi

    echo "> Connecting to NordVPN: ${connect_cmd}"
    if eval "${connect_cmd}"; then
        echo " - Successfully connected to NordVPN. Status:"
        nordvpn status
        RECONNECT_COUNT=0  # Reset counter on successful connection
        return 0
    else
        # If city connection failed, try fallback strategies
        if [[ -n "${NORDVPN_CITY}" && -n "${NORDVPN_COUNTRY}" && "$fallback_attempted" == "false" ]]; then
            echo " - Connection with city failed. Trying country-only fallback..."
            fallback_attempted=true

            # Try just country without city
            local fallback_cmd="nordvpn connect \"${NORDVPN_COUNTRY}\""
            echo "> Fallback connection: ${fallback_cmd}"
            if eval "${fallback_cmd}"; then
                echo " - Successfully connected to NordVPN (country fallback). Status:"
                nordvpn status
                RECONNECT_COUNT=0
                return 0
            fi
        fi

        # Final fallback - just connect to any server
        echo " - All specific connections failed. Connecting to any available server..."
        if nordvpn connect; then
            echo " - Successfully connected to any server. Status:"
            nordvpn status
            RECONNECT_COUNT=0
            return 0
        fi

        return 1
    fi
}

echo "> Initial connection to NordVPN"
if connect_vpn; then
    echo " - Initial connection successful"
else
    do_fail "Failed to establish initial connection to NordVPN."
fi

echo "> Monitoring connection (PID: $)"
echo "> Configuration: Country=${NORDVPN_COUNTRY}, City=${NORDVPN_CITY}, KillSwitch=${NORDVPN_KILLSWITCH}"
echo "> Max reconnect attempts: ${MAX_RECONNECT_ATTEMPTS}, Interval: ${RECONNECT_INTERVAL}s"

# Maintain connection and exit if connection drops
while [[ "$SHUTDOWN" == "false" ]]; do
  # Check if we received a shutdown signal
  if [[ "$SHUTDOWN" == "true" ]]; then
    break
  fi

  # Check connection status
  if ! nordvpn status | grep -q "Connected"; then
    ((RECONNECT_COUNT++))
    echo "> Connection lost. Reconnect attempt ${RECONNECT_COUNT}/${MAX_RECONNECT_ATTEMPTS}..."

    if [[ $RECONNECT_COUNT -le $MAX_RECONNECT_ATTEMPTS ]]; then
        if connect_vpn; then
            echo " - Reconnected successfully"
        else
            echo "> Failed to reconnect. Will retry in ${RECONNECT_INTERVAL} seconds..."
            sleep "${RECONNECT_INTERVAL}"
            continue
        fi
    else
        do_fail "Maximum reconnect attempts (${MAX_RECONNECT_ATTEMPTS}) exceeded. Exiting."
    fi
  fi

  # Sleep with signal-aware mechanism
  for i in $(seq 1 10); do
    [[ "$SHUTDOWN" == "true" ]] && break
    sleep 1
  done
done

echo "> Main loop exited"
cleanup
