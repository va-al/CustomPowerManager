#!/bin/env bash
# Power Management Deployment Script
# Version: 1.0
# Description: Installs power management tools including UDEV rules and management script

# Exit on error, undefined variable, and pipe failures
set -euo pipefail

# Constants
UDEV_RULE_SRC="./99-powersaving.rules"
UDEV_RULE_DEST="/etc/udev/rules.d/99-powersaving.rules"
SCRIPT_SRC="./powerManagement.sh"
SCRIPT_DEST="/usr/local/sbin/powerManagement.sh"
UDEV_RULE_BAK="./99-powersaving.rules.bak"
SCRIPT_BAK="./powerManagement.sh.bak"

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root" >&2
        exit 1
    fi
}

# Function to check if source files exist
check_files() {
    local missing=0

    if [[ ! -f "$UDEV_RULE_SRC" ]]; then
        echo "Error: Source file $UDEV_RULE_SRC not found" >&2
        missing=1
    fi

    if [[ ! -f "$SCRIPT_SRC" ]]; then
        echo "Error: Source file $SCRIPT_SRC not found" >&2
        missing=1
    fi

    if [[ $missing -eq 1 ]]; then
        exit 1
    fi
}

# Function to install files
install_files() {
    echo "Installing power management tools..."

    # Backup existing files to current working directory if they exist
    if [[ -f "$UDEV_RULE_DEST" ]]; then
        cp "$UDEV_RULE_DEST" "$UDEV_RULE_BAK"
        echo "Backed up existing UDEV rule to $UDEV_RULE_BAK"
    fi

    if [[ -f "$SCRIPT_DEST" ]]; then
        cp "$SCRIPT_DEST" "$SCRIPT_BAK"
        echo "Backed up existing script to $SCRIPT_BAK"
    fi

    # Install UDEV rule
    echo "Installing UDEV rule..."
    cp "$UDEV_RULE_SRC" "$UDEV_RULE_DEST"
    chown root:root "$UDEV_RULE_DEST"
    chmod 644 "$UDEV_RULE_DEST"
    echo "✓ UDEV rule installed: $(ls -l "$UDEV_RULE_DEST")"

    # Reload UDEV rules
    echo "Reloading UDEV rules..."
    if udevadm control --reload-rules; then
        echo "✓ UDEV rules reloaded successfully"
    else
        echo "⚠ Failed to reload UDEV rules. Please check manually."
    fi

    # Install management script
    echo "Installing power management script..."
    cp "$SCRIPT_SRC" "$SCRIPT_DEST"
    chown root:root "$SCRIPT_DEST"
    chmod 755 "$SCRIPT_DEST"
    echo "✓ Script installed: $(ls -l "$SCRIPT_DEST")"

    echo "Installation complete!"
}

# Function to run tests
run_tests() {
    echo "Running tests..."

    # Check if files are installed
    local missing=0

    if [[ ! -f "$UDEV_RULE_DEST" ]]; then
        echo "⚠ UDEV rule not installed"
        missing=1
    else
        echo "✓ UDEV rule installed"
    fi

    if [[ ! -f "$SCRIPT_DEST" ]]; then
        echo "⚠ Power management script not installed"
        missing=1
    else
        echo "✓ Power management script installed"

        # Test if script is executable
        if [[ -x "$SCRIPT_DEST" ]]; then
            echo "✓ Script is executable"
        else
            echo "⚠ Script is not executable"
            missing=1
        fi
    fi

    # Add more tests as needed

    if [[ $missing -eq 1 ]]; then
        echo "Some components are not properly installed."
        exit 1
    else
        echo "All tests passed!"
    fi
}

# Function to uninstall files
uninstall_files() {
    echo "Uninstalling power management tools..."

    # Remove UDEV rule
    if [[ -f "$UDEV_RULE_DEST" ]]; then
        rm -f "$UDEV_RULE_DEST"
        echo "✓ UDEV rule removed"
    else
        echo "UDEV rule not found, nothing to remove"
    fi

    # Remove management script
    if [[ -f "$SCRIPT_DEST" ]]; then
        rm -f "$SCRIPT_DEST"
        echo "✓ Power management script removed"
    else
        echo "Power management script not found, nothing to remove"
    fi

    echo "Uninstallation complete!"
}

# Function to clean up backup files
clean_backups() {
    echo "Cleaning up backup files..."

    local found=0

    if [[ -f "$UDEV_RULE_BAK" ]]; then
        rm -f "$UDEV_RULE_BAK"
        echo "✓ Removed UDEV rule backup: $UDEV_RULE_BAK"
        found=1
    fi

    if [[ -f "$SCRIPT_BAK" ]]; then
        rm -f "$SCRIPT_BAK"
        echo "✓ Removed script backup: $SCRIPT_BAK"
        found=1
    fi

    if [[ $found -eq 0 ]]; then
        echo "No backup files found to clean."
    else
        echo "Cleanup complete!"
    fi
}

show_usage () {
    echo "Usage: $(basename "$0") [COMMAND]"
    echo
    echo "Commands:"
    echo "  install    Install power management tools"
    echo "  tests      Run tests to verify installation"
    echo "  uninstall  Remove power management tools"
    echo "  clean      Remove backup files from working directory"
    echo
}

# Main script execution
check_root

# Use "help" as the default argument if none passed in
case  "${1-help}" in
    install)
        check_files
        install_files
        ;;
    tests)
        run_tests
        ;;
    uninstall)
        uninstall_files
        ;;
    clean)
        clean_backups
        ;;
    *)
        show_usage
        exit 1
        ;;
esac

exit 0
