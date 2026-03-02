#!/bin/bash
# kill_port.sh - Kill process running on a specific port

PORT="$1"

if [ -z "$PORT" ]; then
    echo "Error: Port number required"
    exit 1
fi

# Check if port is a valid number
if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
    echo "Error: Port must be a number"
    exit 1
fi

# Find and kill the process
PID=$(lsof -i ":$PORT" 2>/dev/null | grep LISTEN | awk '{print $2}' | head -n 1)

if [ -z "$PID" ]; then
    echo "No process found listening on port $PORT"
    exit 0
fi

# Get process name for confirmation
PROCESS_NAME=$(ps -p "$PID" -o comm= 2>/dev/null)

# Kill the process
if kill -9 "$PID" 2>/dev/null; then
    echo "✓ Killed process $PROCESS_NAME (PID: $PID) on port $PORT"
else
    echo "✗ Failed to kill process on port $PORT (may require sudo)"
    exit 1
fi
