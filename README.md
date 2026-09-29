# MPV Gradual Pause

MPV script that eases pause and unpause instead of cutting them off.

Do the immediate audio cut on pausing media bugs you?
Frustrate no more -> I fade the audio on your music and video experience.

I'm an MPV Script that adds a fade-in and fade-out effect
when pausing or unpausing music/video playback, plus a short picture ease
so the freeze is not a hard cut.

Features an ease-in-out volume curve (with linear and decibel options),
a brief dim/blur on video, MPRIS support, and an end-of-file guard so
`keep-open` does not flicker.

## Features

- **Smooth Audio Transitions**: Fade-out and fade-in with a flat start and end, so the ramp does not click
- **Curves**: Default ease-in-out, plus linear and decibel ramps
- **Soft Picture**: A short dim across the same moment, plus a blur on the legacy `gpu` VO when `sharpen` exists. The still frame is clear again
- **MPRIS Integration**: External pause stays paused (it does not keep playing through the fade). Unpause fades in from silence, including from the OSC and MPRIS
- **End-of-file guard**: A pause from `keep-open` / `eof-reached` is left alone
- **Seeks while paused stick**: Unpause continues from the paused frame, or from wherever you seeked
- **Zero Performance Impact**: Lightweight Lua implementation with negligible CPU usage
- **Debug Mode**: Built-in logging for troubleshooting

## The Problem

By default, MPV (and most media players) instantly cuts audio when you pause, creating a jarring listening experience. This is especially noticeable when:

- Pausing music or podcasts mid-phrase
- Using media keys or MPRIS controls
- Quickly toggling pause during video playback

## The Solution

**gradual-pause** intercepts pause/unpause events and applies smooth volume fading:

- **Fade-out**: Eases volume to 0 while playback continues, then pauses (default: 0.45s)
- **Fade-in**: Eases volume back up from silence (default: 0.45s)
- **Picture**: Softens during that same ramp, then rests on a sharp frame
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
| `fade_in_duration` | float | `0.45` | 0.0 - 5.0 | Fade-in duration in seconds when unpausing |
| `steps` | integer | `12` | 1 - 100 | Legacy rate hint. The ramp is never coarser than 20ms |
| `fade_curve` | string | `auto` | auto, smooth, linear, logarithmic | Ramp shape. `auto` follows `logarithmic_fade` |
| `logarithmic_fade` | boolean | `yes` | yes/no | With `fade_curve=auto`: yes = smooth ease, no = linear |
| `video_transition` | string | `soft` | soft, dim, blur, none | Picture ease. `none` is audio only |
| `video_hold` | boolean | `no` | yes/no | Keep the softened picture for the whole pause |
| `blur_strength` | float | `28` | 0 - 100 | Peak blur on legacy `vo=gpu` only, via `sharpen` |
| `dim_strength` | float | `22` | 0 - 100 | Peak contrast / saturation / brightness dip |
| `restore_position` | boolean | `no` | yes/no | Seek back to the pre-fade time on unpause |
| `debug_mode` | boolean | `no` | yes/no | Enable debug logging to the mpv console |

### Configuration Examples

#### Faster Fades (Snappier Feel)
```ini
fade_out_duration=0.2
fade_in_duration=0.15
```

#### Longer, slower fades
```ini
fade_out_duration=0.7
fade_in_duration=0.7
```

#### Linear ramp (constant rate on the volume property)
```ini
fade_curve=linear
```

#### Decibel ramp
```ini
fade_curve=logarithmic
```

#### Audio only
```ini
video_transition=none
```

#### Keep the paused frame soft
```ini
video_hold=yes
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
3. **Pause from the OSC, a media key, or MPRIS** → playback stops immediately and stays stopped. Audible volume is held at 0, so unpause fades in instead of blasting full volume. The picture can still ease while the frame is frozen.
4. **Unpause from those same controls** → audio rises from silence. It does not start at full volume and then drop.

Keyboard pause is the one that fades audio out while the file is still playing, because the script sees the key before mpv pauses. An external pause has already paused by the time the script runs, and the script does not unpause it to manufacture a fade.

## How It Works

### Technical Overview

1. **Key binding override**: `space` and `p` go through the script (`add_forced_key_binding`)
2. **Property observation**: the `pause` property covers MPRIS, the OSC, and media keys
3. **Volume ramp**: a timer samples a continuous curve at least every 20ms, without the OSD bar
4. **No backward seek**: a keyboard fade-out keeps playing, then pauses on the later frame. Unpause continues from that frame, so a seek made while paused is still there. An external pause does not resume playback
5. **Picture ease**: contrast, saturation, and brightness dip during the ramp. Blur is only the legacy `gpu` VO's `sharpen` property, and only when that property exists. `gpu-next` and current mpv builds without `sharpen` get the dim alone. With `video_hold=no` the effect peaks mid-fade and the still frame is sharp
6. **End of file**: a pause that arrives with `eof-reached` (or while idle) is not treated as a user pause
7. **Silent hold**: after a script pause, the volume property stays 0 until fade-in. That is what keeps an OSC/MPRIS unpause from starting at full volume. The saved level is restored when the fade-in finishes, and again on file end or shutdown

`observe_property` cannot cancel a pause, and its return value is ignored. Script pause writes are matched against the delivered value (and cleared if mpv coalesces them), including across file loads.

### Curves

mpv turns the `volume` property into gain with a cube (`gain = (volume/100)^3`).

**Smooth** (default): loudness moves roughly evenly in decibels, from full volume down to about -36 dB (and back). The first and last moments are eased so the ramp does not corner. This is the curve that stays gradual on unpause.

**Linear**: constant slope on the volume property. Set `fade_curve=linear` or `logarithmic_fade=no`.

**Logarithmic**: the same kind of decibel ramp, with a deeper floor (about -48 dB). Set `fade_curve=logarithmic`.

### Picture transition

| `video_transition` | What you get |
| --- | --- |
| `soft` (default) | Dim on any VO that exposes the equalizer. On legacy `vo=gpu`, also a `sharpen` blur when that property exists |
| `dim` | Equalizer only |
| `blur` | `sharpen` blur on legacy `vo=gpu`; every other VO, including `gpu-next`, falls back to dim |
| `none` | Audio only |

`blur_strength` and `dim_strength` scale the peak. The blur is not a libavfilter graph. `gpu-next` does not honor `sharpen`, and newer mpv removed the property, so those setups stay on the dim.

`restore_position=yes` seeks back to where fade-out began, which is the old behavior and does cut the picture. A seek that moved `time-pos` more than 0.25s while paused is kept either way.

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

You should see: `gradual_pause v1.1.0 loaded` when `debug_mode=yes`

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
# Curve, seek, eof, and picture-ease behavior without a display
lua5.4 tests/run_unit.lua

# Same checks inside mpv (needs mpv and ffmpeg on PATH)
sh tests/run_integration.sh

# Listen to it
mpv --script=./scripts/gradual_pause.lua \
    --script-opts=gradual_pause-debug_mode=yes \
    video.mp4
```

Manual pass:

1. Pause with `space`. Audio should ease down with no click on the first moment, and the picture should soften then rest sharp on a later frame (not a jump backward).
2. Seek while paused, then unpause. Playback continues from the seek, fading in from silence.
3. Unpause without seeking. Audio eases up from the paused frame; it does not replay the fade-out.
4. Let a file hit the end with `keep-open=yes`. The player stays paused and does not fade or replay the tail.
5. Pause from the OSC or MPRIS. Playback should stop at once and stay stopped (no extra half-second of the file). Unpause should fade in from silence, not from full volume.

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
