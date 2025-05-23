# CustomPowerManager
Set of scripts for custom power settings and battery conservation. The scripts are made for Lenovo laptops.

Copyright Vaal 2025
The script should be running by UDEV, triggering by power adapter connect \ disconnect events.
As an bonus option it can change Lenovo Battery conservation mode setting.

TODO
- desktop notifications. It's complicated for root user, under which udev daemon strat the script.
It seems you should determine some dbus and session IDs before you can send desktop notification from root.
- add environment zeroing and other best practices for safe start, use shellcheck
- (?) when we're on AC and the battery is reached 75% reqest a user if they wants to switch to conservation mode
  this probably require an additional UDEV rule tho

UDEV rule e.g.
99-powersaving.rules
ACTION=="change", KERNEL=="ACAD", SUBSYSTEM=="power_supply", ATTR{online}=="1", RUN+="/usr/local/sbin/powerManagement.sh AC"
ACTION=="change", KERNEL=="ACAD", SUBSYSTEM=="power_supply", ATTR{online}=="0", RUN+="/usr/local/sbin/powerManagement.sh BAT"

set -e  # Exit on error
