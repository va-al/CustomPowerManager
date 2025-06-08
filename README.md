# CustomPowerManager
Set of scripts for custom power settings and battery conservation. The scripts are made for Lenovo laptops.

Copyright Vaal 2025

The script should be running by UDEV, triggering by power adapter connect \ disconnect events.
As an bonus option it can change Lenovo Battery conservation mode setting.

## Installation

Use the provided deployment script to install the power management tools:

```bash
sudo ./deploy.sh install
```

This will install:
- UDEV rule to `/etc/udev/rules.d/99-powersaving.rules`
- Power management script to `/usr/local/sbin/powerManagement.sh`
- Symlink `pm` to `/usr/local/bin/pm` for easy access

## Usage

After installation, you can run the power management script in two ways:

1. **Direct execution**: `/usr/local/sbin/powerManagement.sh [AC|BAT]`
2. **Using symlink**: `pm [AC|BAT]` (available from anywhere in the system)

The script will be automatically triggered by UDEV when power adapter events occur.

## Deployment Script Commands

- `sudo ./deploy.sh install` - Install power management tools
- `sudo ./deploy.sh tests` - Run tests to verify installation
- `sudo ./deploy.sh uninstall` - Remove power management tools
- `sudo ./deploy.sh clean` - Remove backup files from working directory
- `sudo ./deploy.sh all` - Install, test, and clean (GOD Mode)

## TODO

- desktop notifications. It's complicated for root user, under which udev daemon start the script.
It seems you should determine some dbus and session IDs before you can send desktop notification from root.
- add environment zeroing and other best practices for safe start, use shellcheck
- (?) when we're on AC and the battery is reached 75% request a user if they wants to switch to conservation mode
  this probably require an additional UDEV rule tho

## UDEV Rule Example

```
99-powersaving.rules
ACTION=="change", KERNEL=="ACAD", SUBSYSTEM=="power_supply", ATTR{online}=="1", RUN+="/usr/local/sbin/powerManagement.sh AC"
ACTION=="change", KERNEL=="ACAD", SUBSYSTEM=="power_supply", ATTR{online}=="0", RUN+="/usr/local/sbin/powerManagement.sh BAT"
```
