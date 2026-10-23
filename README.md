# keepingawake

A tiny macOS menu bar app that keeps your Mac awake, **even with the lid closed**.

Inspired by [KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake), which prevents idle sleep but cannot stop the Mac from sleeping when you close the lid. keepingawake does both.

- Native Swift + AppKit, a single source file
- ~16 MB of memory, no CPU while idle
- No dependencies, no Xcode project

## Usage

| Action | Result |
|---|---|
| Left click on the cup | Toggle on / off (full cup = active) |
| Right click (or Control-click) | Menu: **Launch at Login**, **Quit** |

When active:

- the display does not turn off and the Mac does not go to sleep from inactivity;
- the Mac keeps running when you close the lid, with or without an external display.

Normal sleep behavior is restored when you turn it off, quit the app, log out, or kill the process. If the app crashes while active, sleep is restored the next time it launches.

> ⚠️ While active, a closed MacBook keeps running. Turn it off before putting the laptop in a bag, or it will heat up and drain the battery.

## How it works

**Idle sleep** is blocked with IOKit power assertions (`PreventUserIdleDisplaySleep` and `PreventUserIdleSystemSleep`). This is the same mechanism `caffeinate` uses, and it needs no special privileges.

**Lid-close sleep** cannot be blocked by assertions. macOS sleeps on lid close regardless, unless sleep is disabled system-wide:

```sh
pmset -a disablesleep 1   # on
pmset -a disablesleep 0   # off
```

This setting requires root. On first activation, keepingawake shows the standard macOS administrator password dialog once and installs a sudoers rule at `/etc/sudoers.d/keepingawake`:

```
<user> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

The rule allows exactly those two commands and nothing else. After that, the app toggles the setting through `sudo -n` without asking again. If you cancel the dialog, the app still prevents idle sleep, but the Mac will sleep when the lid is closed.

## Build and install

Requires macOS 14+ and Xcode, which provides `actool` to compile the app icon.

```sh
make install      # build and copy to /Applications
open /Applications/keepingawake.app
```

Other targets:

```sh
make sudoers      # install the sudoers rule manually instead of via the in-app dialog
make uninstall    # remove the app and the sudoers rule, re-enable sleep
make clean
```

## Credits

Menu bar and app icons are from [KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake) by Marcel Dierkes, MIT License. See [LICENSE](LICENSE).
