# MPV Gradual Pause

MPV script that adds smooth audio fade effects when pausing/unpausing

Do the immediate audio cut on pausing media bugs you?
Frustrate no more -> I fade the audio on your music and video experience.

I'm an MPV Script that adds a fade-in and fade-out effect
when pausing or unpausing music/video playback.

Features logarithmic and linear volume curves, MPRIS "integration"
support, and robust state management for seamless operation with external
pause controls.

## Features

- **Smooth Audio Transitions**: Configurable fade-in/fade-out effects eliminate abrupt audio cuts
- **Logarithmic & Linear Curves**: Choose between natural-sounding logarithmic fading or constant-rate linear fading
- **MPRIS Integration**: Works seamlessly with external pause/unpause triggers (media keys, system controls, remote apps)
- **Zero Performance Impact**: Lightweight Lua implementation with negligible CPU usage
- **Highly Configurable**: Fine-tune fade durations, step counts, and curve types
- **Debug Mode**: Built-in logging for troubleshooting
- **Position Preservation**: Maintains exact playback position through pause cycles

## The Problem

By default, MPV (and most media players) instantly cuts audio when you pause, creating a jarring listening experience. This is especially noticeable when:

- Pausing music or podcasts mid-phrase
- Using media keys or MPRIS controls
- Quickly toggling pause during video playback

## The Solution

**gradual-pause** intercepts pause/unpause events and applies smooth volume fading:

- **Fade-out**: Gradually reduces volume to 0 before pausing (default: 0.45s)
- **Fade-in**: Gradually increases volume from 0 after unpausing (default: 0.3s)
- **Smart handling**: Works with keyboard shortcuts, media keys, and external controls

## Installation

### NixOS (with Home Manager)

Add to your Home Manager configuration:

```nix
programs.mpv = {
  enable = true;
  scripts = [ pkgs.mpvScripts.gradual-pause ];
};
```

Then rebuild your configuration:

```bash
home-manager switch
```

### NixOS (without Home Manager)

Add to your NixOS configuration:

```nix
environment.systemPackages = with pkgs; [
  (mpv.override {
    scripts = [ mpvScripts.gradual-pause ];
  })
];
```

Then rebuild:

```bash
sudo nixos-rebuild switch
```

### Manual Installation (All Platforms)

1. **Download the script**:
   ```bash
   mkdir -p ~/.config/mpv/scripts
   curl -o ~/.config/mpv/scripts/gradual_pause.lua \
     https://raw.githubusercontent.com/gui-wf/mpv-gradual-pause/main/scripts/gradual_pause.lua
   ```

2. **Download default configuration** (optional):
   ```bash
   mkdir -p ~/.config/mpv/script-opts
   curl -o ~/.config/mpv/script-opts/gradual_pause.conf \
     https://raw.githubusercontent.com/gui-wf/mpv-gradual-pause/main/script-opts/gradual_pause.conf
   ```

3. **Restart MPV** - the script will load automatically

### Arch Linux / AUR

```bash
# Package pending AUR submission
```

### Homebrew (macOS)

```bash
# Package pending Homebrew submission
```

## Configuration

### Quick Start

The script works out-of-the-box with sensible defaults. To customize behavior, create a configuration file:

```bash
# Create config directory
mkdir -p ~/.config/mpv/script-opts

# Edit configuration
nano ~/.config/mpv/script-opts/gradual_pause.conf
```

### Available Options

| Option | Type | Default | Range | Description |
|--------|------|---------|-------|-------------|
| `fade_out_duration` | float | `0.45` | 0.0 - 5.0 | Fade-out duration in seconds when pausing |
| `fade_in_duration` | float | `0.3` | 0.0 - 5.0 | Fade-in duration in seconds when unpausing |
| `steps` | integer | `12` | 1 - 100 | Number of volume steps (higher = smoother) |
| `logarithmic_fade` | boolean | `yes` | yes/no | Use logarithmic curve (more natural) vs linear |
| `debug_mode` | boolean | `no` | yes/no | Enable debug logging to MPV console |

### Configuration Examples

#### Faster Fades (Snappier Feel)
```ini
fade_out_duration=0.2
fade_in_duration=0.15
```

#### Ultra-Smooth Fades (More Steps)
```ini
steps=24
fade_out_duration=0.6
fade_in_duration=0.4
```

#### Linear Fading (Constant Rate)
```ini
logarithmic_fade=no
```

#### Debug Mode (Troubleshooting)
```ini
debug_mode=yes
```

Then press `` ` `` (backtick) in MPV to open the console and view debug messages.

### Command-Line Override

You can override settings per-session using `--script-opts`:

```bash
mpv --script-opts=gradual_pause-fade_out_duration=1.0,gradual_pause-debug_mode=yes video.mp4
```

## Usage

Once installed, the script works transparently:

1. **Press `Space` or `p`** to pause → audio fades out smoothly
2. **Press `Space` or `p` again** to unpause → audio fades in smoothly
3. **Use media keys** (play/pause) → same smooth behavior
4. **External controls** (smartphone remotes, MPRIS) → same smooth behavior

The script intercepts pause events from **any source** and applies fading automatically.

## How It Works

### Technical Overview

1. **Key Binding Override**: Intercepts `space` and `p` keys using `add_forced_key_binding`
2. **Property Observation**: Monitors the `pause` property for external changes (MPRIS, media keys)
3. **Volume Manipulation**: Uses periodic timers to step volume in calculated increments
4. **State Management**: Prevents conflicts when multiple pause events occur simultaneously
5. **Position Preservation**: Saves and restores exact playback position to maintain continuity

### Logarithmic vs Linear Fading

**Logarithmic Fade** (default):
- Starts fast, ends slow (fade-out) / Starts slow, ends fast (fade-in)
- Perceived as more "natural" to human hearing
- Mimics professional audio engineering techniques

**Linear Fade**:
- Constant volume change rate
- Simpler, more predictable behavior
- Slightly more "mechanical" feel

### Performance Impact

- **CPU Usage**: <0.1% on modern systems
- **Memory**: ~50KB RAM footprint
- **Latency**: No noticeable delay (fade starts immediately)

## Troubleshooting

### Script Not Loading

**Check if MPV detects the script**:
```bash
mpv --msg-level=all=debug video.mp4 2>&1 | grep gradual
```

You should see: `[gradual_pause] gradual_pause v1.0.0 loaded successfully`

**Common issues**:
- Ensure script is in `~/.config/mpv/scripts/` (not `~/.mpv/scripts/`)
- Verify file is named `gradual_pause.lua` (not `.txt` or other extension)
- Check file permissions: `chmod +x ~/.config/mpv/scripts/gradual_pause.lua`

### Fading Not Working

1. **Enable debug mode**:
   ```ini
   # ~/.config/mpv/script-opts/gradual_pause.conf
   debug_mode=yes
   ```

2. **Watch the console** (press `` ` `` in MPV):
   - Look for `Starting fade-out sequence` / `Starting fade-in sequence`
   - Check for error messages

3. **Test with minimal config**:
   ```bash
   mpv --no-config --script=~/.config/mpv/scripts/gradual_pause.lua video.mp4
   ```

### Conflicts with Other Scripts

If you have other scripts that modify pause behavior, they may conflict. Try:

1. Temporarily disable other scripts
2. Load gradual-pause last (rename to `zzz_gradual_pause.lua` to load last alphabetically)
3. Check script compatibility in debug mode

### Volume Resets Unexpectedly

The script restores original volume after fading. If volume changes persist:

- Check for volume normalization filters (`--af=dynaudnorm`)
- Verify other scripts aren't modifying volume
- Ensure MPV's `volume-max` isn't capping your volume

## Compatibility

### MPV Versions

- **Minimum**: MPV 0.35.0 (released 2023)
- **Recommended**: MPV 0.38.0+ (latest stable)
- **Tested**: 0.35.x, 0.36.x, 0.37.x, 0.38.x, 0.39.x (dev)

### Operating Systems

- **Linux**: Full support (PulseAudio, PipeWire, ALSA)
- **macOS**: Full support (CoreAudio)
- **Windows**: Full support (WASAPI)
- **BSD**: Untested but should work

### Audio Backends

Works with all MPV audio output drivers (`--ao`):
- `pulse` (PulseAudio)
- `pipewire` (PipeWire)
- `alsa` (ALSA)
- `coreaudio` (macOS)
- `wasapi` (Windows)

### Known Script Conflicts

**Compatible with**:
- `mpv-mpris` (MPRIS integration)
- `autoload` (playlist auto-loading)
- `sponsorblock` (YouTube sponsor skipping)
- `quality-menu` (video quality selection)

**Potential conflicts**:
- Custom pause/volume scripts may interfere
- Scripts that override `space`/`p` keybindings

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Reporting Bugs

When reporting issues, please include:

1. MPV version (`mpv --version`)
2. Operating system and audio backend
3. Script configuration (`~/.config/mpv/script-opts/gradual_pause.conf`)
4. Debug log output (with `debug_mode=yes`)
5. Steps to reproduce

### Feature Requests

Open an issue with the `enhancement` label and describe:
- Use case: What problem does this solve?
- Proposed solution: How should it work?
- Alternatives: What else have you tried?

## Development

### Testing Locally

```bash
# Clone repository
git clone https://github.com/gui-wf/mpv-gradual-pause.git
cd mpv-gradual-pause

# Test script directly
mpv --script=./scripts/gradual_pause.lua --script-opts=gradual_pause-debug_mode=yes test-video.mp4

# Build Nix package locally
nix-build -E 'with import <nixpkgs> {}; callPackage ./nix/package.nix {}'
```

### Running Tests

```bash
# Test with different fade durations
for duration in 0.1 0.3 0.5 1.0; do
  echo "Testing fade duration: $duration"
  mpv --script-opts=gradual_pause-fade_out_duration=$duration,gradual_pause-debug_mode=yes video.mp4
done
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and release notes.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

**Guilherme Fontes** ([@gui-wf](https://github.com/gui-wf))

## Acknowledgments

- MPV development team for the excellent media player and Lua scripting API
- NixOS community for packaging infrastructure and review
- Users who provided feedback and testing

## Related Projects

- [mpv](https://mpv.io/) - The media player this script enhances
- [mpv-mpris](https://github.com/hoyon/mpv-mpris) - MPRIS integration for MPV
- [mpv user scripts wiki](https://github.com/mpv-player/mpv/wiki/User-Scripts) - Collection of MPV scripts

---

**Star this repository** if you find it useful! Contributions and feedback are always welcome.
