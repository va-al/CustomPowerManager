#!/usr/bin/env bash

# Copyright Vaal, 2025
# The script should be running by UDEV, triggering by power adapter connect \ disconnect events.
# As an bonus option it can change Lenovo Battery conservation mode setting.
# check ./README.md for more information

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit if any command in a pipe fails

# Clear environment for safety
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
IFS=$' \t\n'


##############################################################################################################################
# Configuration
##############################################################################################################################
tag=$(basename "$0") # define selfname for logging

# Define battery conservation interface
CMFile="/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode"

# Defince current battery conservation status
CMStatus=$(cat "$CMFile")

ppdSavingProfile="power-saver" # can be performance balanced power-saver
ppdPerfProfile="performance" # can be performance balanced power-saver
energyPerfPref="power" # can be default performance balance_performance balance_power power

##############################################################################################################################
# Messages Configuration
##############################################################################################################################
logACDone="✓ Power adapter has been plugged in. High power settings successfully applied"
logBATDone="✓ Power adapter has been plugged out. Battery power saving mode successfully applied."
logCMOn="✓ The Battery conservation mode successfully ON"
logCMOff="✓ The Battery conservation mode successfully OFF"
logNoArgs="⚠ This script should be called with proper arguments. Please use AC, BAT, CP or CM on\\off."
logCMOffUsage="⚠ Battery Conservation mode is switched OFF now. Please use the script with proper arguments."
echoCMOffUsage="⚠ Battery Conservation mode is switched OFF now. Please use \\n\\n \
             sudo $tag CM on \\n\\n or \\n\\n sudo $tag CM off \\n\\n respectively to change the setting"
logCMOnUsage="⚠ Battery Conservation mode is switched ON now. Please use the script with proper arguments."
echoCMOnUsage=" ⚠ Battery Conservation mode is switched ON now. Please use \\n\\n sudo $tag CM on \\n\\n \
                or \\n\\n sudo $tag CM off \\n\\n respectively to change the setting"
logNoRoot="⚠ This script should be run as root."
##############################################################################################################################

ScalingGovernor="None"
EPP="None"
PlatformProfile="None"
ConservationStatus=0

# Check resources availability
if [[ ! -f "$CMFile" ]]; then
    echo "⚠ Conservation mode file not found at $CMFile. This script may not work properly on your system." >&2
    logger -p err -i -t "$tag" "⚠ Conservation mode file not found at $CMFile"
    exit 1
fi

# Required commands
for cmd in powerprofilesctl powertop logger; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "⚠ Required command '$cmd' not found. Please install it." >&2
        exit 1
    fi
done

# Function definitions with proper quoting and error handling
# Print a message to the console, supporting escape sequences.
consoleLog() { echo -e "$1"; }

# Log a message to syslog with the specified priority and tag.
log() { logger -p "$1" -i -t "$tag" "$2"; }

# Ensure the script is running as root, otherwise exit.
checkIfRoot() {
    if [[ $EUID -ne 0 ]]; then
        log "err" "$logNoRoot"
        consoleLog "$logNoRoot"
        exit 1
    fi
}

# Set the power profile using powerprofilesctl.
ppdProfileSet() {
    if ! powerprofilesctl set "$1" &>/dev/null; then
        log "err" "⚠ Failed to set power profile to $1"
        return 1
    fi
    return 0
}

# Apply battery conservation mode by writing to the sysfs interface.
CMApply() {
    if ! echo "$1" > "$CMFile" 2>/dev/null; then
        log "err" "⚠ Failed to set conservation mode to $1"
        return 1
    fi
    return 0
}

# Apply powertop auto-tune optimizations.
PowerTopApply() {
        if ! powertop -q --auto-tune &>/dev/null; then
        log "err" "⚠ Failed to apply powertop optimizations"
        return 1
    fi
    return 0
}

# Set the energy performance preference for all CPUs.
EPPApply() {
    local success=true
    for epp_file in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        if [[ -f "$epp_file" ]]; then
            if ! echo "$1" > "$epp_file" 2>/dev/null; then
                success=false
            fi
        fi
    done

    if [[ "$success" == "false" ]]; then
        log "err" "⚠ Failed to set energy performance preference to $1"
        return 1
    fi
    return 0
}

# Read and display the current power and battery conservation settings from sysfs.
checkProfilesNow () {
        if ! read -r ScalingGovernor EPP PlatformProfile ConservationStatus < <(echo "$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | uniq) \
             $(cat /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference | uniq) \
             $(cat /sys/firmware/acpi/platform_profile) \
             $(cat /sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode)"); then
        log "err" "⚠ Failed to read current settings from /sys"
        return 1
        fi
    echo -e "✓ Scaling governor is \033[1m$ScalingGovernor\033[0m now"
    echo -e "✓ Energy Performance setting is \033[1m$EPP\033[0m now"
    echo -e "✓ Platform Profile is \033[1m$PlatformProfile\033[0m now"
        if [[ ConservationStatus -eq 1 ]]; then
            echo -e "✓ Battery Conservation mode is switched \033[1mON\033[0m now"
        else
            echo -e "✓ Battery Conservation mode is switched \033[1mOFF\033[0m now"
        fi
    return 0

}

# Validate input arguments
if [[ $# -lt 1 ]]; then
    log "err" "$logNoArgs"
    consoleLog "$logNoArgs"
    exit 1
fi

# Main logic
case "$1" in
    # Unleash the beast!
    "AC")
        checkIfRoot
        ppdProfileSet "$ppdPerfProfile"
        log "notice" "$logACDone"
        checkProfilesNow
        ;;

    # Let's be more humble on energy consuming
    "BAT")
        checkIfRoot
        # shellcheck disable=SC2015
        # SC2015 suppressed: powertop returns non-zero even on success, so we ignore its exit code intentionally.
        ppdProfileSet "$ppdSavingProfile" && \
        EPPApply "$energyPerfPref" && \
        PowerTopApply || true # this is a dirty hack to handle err when you start powertop with an almost empty ENV.
        # Powertop works correctly, although it returns err exit code
        log "notice" "$logBATDone"
        checkProfilesNow
        ;;

    # Conservation Mode
    "CM")
        # Validate second argument
        case "${2:-}" in
            "on")
                checkIfRoot
                CMApply 1 && \
                log "notice" "$logCMOn" && \
                consoleLog "$logCMOn"
                ;;

            "off")
                checkIfRoot
                CMApply 0 && \
                log "notice" "$logCMOff" && \
                consoleLog "$logCMOff"
                ;;

            # A tiny help for a user
            *)
                if [[ $CMStatus -eq 0 ]]; then
                    log "warn" "$logCMOffUsage" && \
                    consoleLog "$echoCMOffUsage"
                else
                    log "warn" "$logCMOnUsage" && \
                    consoleLog "$echoCMOnUsage"
                fi
                ;;
        esac
        ;;

    "CP")
        checkProfilesNow
        ;;
    *)
        # Sorry bro, but we need some valid arguments to start
        log "err" "$logNoArgs"
        consoleLog "$logNoArgs"
        exit 1
        ;;
esac

exit 0
