---
name: Bug Report
about: Report a bug or unexpected behavior
title: '[BUG] '
labels: bug
assignees: ''
---

## Bug Description

A clear and concise description of what the bug is.

## Steps to Reproduce

1. Go to '...'
2. Press '...'
3. See error

## Expected Behavior

A clear description of what you expected to happen.

## Actual Behavior

A clear description of what actually happened.

## Environment

**MPV Version:**
```
# Output of: mpv --version
```

**Operating System:**
- Distribution: (e.g., NixOS 24.11, Ubuntu 24.04, macOS 14.2, Windows 11)
- Audio Backend: (e.g., pulse, pipewire, alsa, coreaudio, wasapi)

**Script Configuration:**
```ini
# Contents of ~/.config/mpv/script-opts/gradual_pause.conf
# Or "using defaults" if no custom config
```

## Debug Log

Please enable debug mode and provide relevant log output:

1. Add `debug_mode=yes` to `~/.config/mpv/script-opts/gradual_pause.conf`
2. Press `` ` `` (backtick) in MPV to open console
3. Reproduce the issue
4. Copy relevant log lines here

```
# Paste debug log here
```

## Additional Context

Add any other context about the problem here (screenshots, recordings, related issues, etc.)
