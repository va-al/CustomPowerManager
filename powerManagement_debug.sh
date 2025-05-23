#!/bin/env bash

# Copyright vaal, 2025
# The script should be running by UDEV, triggering by power adapter connect \ disconnect events.
# As an bonus option it can change Lenovo Battery conservation mode setting.

# Debug mode - write extensive logs
DEBUG=1

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit if any command in a pipe fails

# Clear environment for safety
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
IFS=$' \t\n'

# Debug log function
debug_log() {
    if [[ $DEBUG -eq 1 ]]; then
        echo "[DEBUG] $1" >> /tmp/powermanagement_debug.log
    fi
}

# Log script start and environment
debug_log "================== Script started at $(date) =================="
debug_log "USER=$(whoami)"
debug_log "PWD=$(pwd)"
debug_log "Arguments: $*"
debug_log "Environment variables:"
env | sort >> /tmp/powermanagement_debug.log

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" >&2
    debug_log "Not running as root, exiting"
    exit 1
fi

##############################################################################################################################
# Configuration
##############################################################################################################################
tag=$(basename "$0") # define selfname for logging

# Define battery conservation interface
CMFile="/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode"

# Check conservation mode file exists
if [[ -f "$CMFile" ]]; then
    # Define current battery conservation status
    CMStatus=$(cat "$CMFile")
    debug_log "Found conservation mode file: $CMFile with status: $CMStatus"
else
    debug_log "Conservation mode file not found: $CMFile"
    CMStatus=0
fi

ppdSavingProfile="balanced" # can be performance balanced power-saver
ppdPerfProfile="performance" # can be performance balanced power-saver
energyPerfPref="balance_power" # can be default performance balance_performance balance_power power

##############################################################################################################################
# Messages Configuration
##############################################################################################################################
logACDone="✓ Power adapter has been plugged in. High power settings successfully applied"
logBATDone="✓ Power adapter has been plugged out. Battery power saving mode successfully applied."
logCMOn="✓ The Battery conservation mode successfully ON"
logCMOff="✓ The Battery conservation mode successfully OFF"
logNoArgs="⚠ This script should be called with proper arguments. Please use AC, BAT or CM on\\off."
logCMOffUsage="⚠ Battery Conservation mode is switched OFF now. Please use the script with proper arguments."
echoCMOffUsage="⚠ Battery Conservation mode is switched OFF now. Please use \\n\\n \
             sudo $tag CM on \\n\\n or \\n\\n sudo $tag CM off \\n\\n respectively to change the setting"
logCMOnUsage="⚠ Battery Conservation mode is switched ON now. Please use the script with proper arguments."
echoCMOnUsage=" ⚠ Battery Conservation mode is switched ON now. Please use \\n\\n sudo $tag CM on \\n\\n \
                or \\n\\n sudo $tag CM off \\n\\n respectively to change the setting"
##############################################################################################################################

# Check resources availability
if [[ ! -f "$CMFile" ]]; then
    echo "⚠ Conservation mode file not found at $CMFile. This script may not work properly on your system." >&2
    logger -p err -i -t "$tag" "⚠ Conservation mode file not found at $CMFile"
    debug_log "Conservation mode file not found, exiting"
    exit 1
fi

# Check for required commands with detailed debug
debug_log "Checking for required commands..."
for cmd in powerprofilesctl powertop logger; do
    if command -v "$cmd" &>/dev/null; then
        debug_log "✓ Found command: $cmd at $(command -v "$cmd")"
    else
        debug_log "✗ Command not found: $cmd"
        echo "⚠ Required command '$cmd' not found. Please install it." >&2
        exit 1
    fi
done

# Function definitions with proper quoting and error handling
consoleLog() { echo -e "$1"; }
log() {
    logger -p "$1" -i -t "$tag" "$2"
    debug_log "LOGGER[$1]: $2"
}

ppdProfileSet() {
    debug_log "Setting power profile to: $1"
    if powerprofilesctl set "$1" 2>/tmp/ppd_error.log; then
        debug_log "✓ Successfully set power profile to $1"
        return 0
    else
        debug_log "✗ Failed to set power profile to $1. Error: $(cat /tmp/ppd_error.log)"
        log "err" "⚠ Failed to set power profile to $1"
        return 1
    fi
}

CMApply() {
    debug_log "Setting conservation mode to: $1"
    if echo "$1" > "$CMFile" 2>/tmp/cm_error.log; then
        debug_log "✓ Successfully set conservation mode to $1"
        return 0
    else
        debug_log "✗ Failed to set conservation mode to $1. Error: $(cat /tmp/cm_error.log)"
        log "err" "⚠ Failed to set conservation mode to $1"
        return 1
    fi
}

PowerTopApply() {
    debug_log "Applying powertop optimizations..."
    # First check if powertop is available
    if ! command -v powertop &>/dev/null; then
        debug_log "✗ powertop command not found in PATH"
        log "err" "⚠ powertop command not found in PATH"
        return 1
    fi

    # Try with absolute path
    local powertop_cmd
    powertop_cmd=$(command -v powertop)
    debug_log "Using powertop at: $powertop_cmd"

    # Try running powertop with full debug
    debug_log "Running: $powertop_cmd -q --auto-tune"
    if "$powertop_cmd" -q --auto-tune >/tmp/powertop_output.log 2>/tmp/powertop_error.log; then
        debug_log "✓ Successfully applied powertop optimizations"
        return 0
    else
        debug_log "✗ Failed to apply powertop optimizations"
        debug_log "powertop stdout: $(cat /tmp/powertop_output.log)"
        debug_log "powertop stderr: $(cat /tmp/powertop_error.log)"
        log "err" "⚠ Failed to apply powertop optimizations"
        return 1
    fi
}

EPPApply() {
    debug_log "Setting energy performance preference to: $1"
    local success=true
    local epp_count=0

    for epp_file in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        if [[ -f "$epp_file" ]]; then
            epp_count=$((epp_count + 1))
            debug_log "Writing '$1' to $epp_file"
            if ! echo "$1" > "$epp_file" 2>/tmp/epp_error.log; then
                debug_log "✗ Failed to write to $epp_file: $(cat /tmp/epp_error.log)"
                success=false
            fi
        fi
    done

    debug_log "Found $epp_count EPP files"

    if [[ "$success" == "false" ]]; then
        log "err" "⚠ Failed to set energy performance preference to $1"
        return 1
    fi

    debug_log "✓ Successfully set energy performance preference to $1"
    return 0
}

# Validate input arguments
if [[ $# -lt 1 ]]; then
    log "err" "$logNoArgs"
    consoleLog "$logNoArgs"
    debug_log "No arguments provided, exiting"
    exit 1
fi

# Main logic
debug_log "Processing command: $1"
case "$1" in
    # Unleash the beast!
    "AC")
        debug_log "AC power mode requested"
        if ppdProfileSet "$ppdPerfProfile"; then
            log "notice" "$logACDone"
        fi
        ;;

    # Let's be more humble on energy consuming
    "BAT")
        debug_log "Battery power mode requested"

        debug_log "Step 1: Setting power profile"
        ppdProfileSet "$ppdSavingProfile"
        debug_log "Step 1 result: $?"

        debug_log "Step 2: Setting energy performance preference"
        EPPApply "$energyPerfPref"
        debug_log "Step 2 result: $?"

        debug_log "Step 3: Applying powertop optimizations"
        PowerTopApply
        debug_log "Step 3 result: $?"

        log "notice" "$logBATDone"
        ;;

    # Conservation Mode
    "CM")
        debug_log "Conservation mode requested with arg: ${2:-none}"
        # Validate second argument
        case "${2:-}" in
            "on")
                CMApply 1 && \
                log "notice" "$logCMOn" && \
                consoleLog "$logCMOn"
                ;;

            "off")
                CMApply 0 && \
                log "notice" "$logCMOff" && \
                consoleLog "$logCMOff"
                ;;

            # A tiny help for a user
            *)
                if [[ $CMStatus -eq 0 ]]; then
                    log "warn" "$logCMOffUsage"
                    consoleLog "$echoCMOffUsage"
                else
                    log "warn" "$logCMOnUsage"
                    consoleLog "$echoCMOnUsage"
                fi
                ;;
        esac
        ;;

    *)
        # Sorry bro, but we need some valid arguments to start
        debug_log "Invalid argument: $1"
        log "err" "$logNoArgs"
        consoleLog "$logNoArgs"
        exit 1
        ;;
esac

debug_log "Script finished successfully at $(date)"
exit 0
