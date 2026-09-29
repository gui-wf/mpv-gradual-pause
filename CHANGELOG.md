# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Unpause no longer seeks back to the pre-fade timestamp. That seek restarted
  the audio decoder, cut the picture to an earlier frame, and discarded seeks
  made while paused. Resume continues from the frame where the fade settled.
  `restore_position=yes` opts into the old seek and still leaves a paused seek
  alone (more than 0.25s from where playback paused).
- The default ramp is even in loudness (decibels), with eased corners. The
  previous "logarithmic" parabola was steepest on the first step (a measured
  fade-out jumped 80 → 67 in one tick, about 4.6 dB). A pure ease on the
  volume slider was the other failure mode: mpv's cubic gain map hid that
  curve in silence, then the sound swelled late in the unpause.
- Volume updates are at most 20ms apart, so a low `steps` value cannot zipper.
  Updates use `no-osd set`, so the volume bar does not flash on every step.
- The initial `pause` property notification is ignored. It used to be handled
  as an unpause and ducked the start of every file to silence.
- Pause caused by end-of-file (`eof-reached`, including `keep-open`) or idle
  is not faded. The fade path was unpausing a finished file and playing the
  tail again. Space / `p` at that point toggle pause directly.
- Script-owned pause writes are ignored with a counter. Returning from
  `observe_property` does not cancel the change. A pause that arrives during
  a fade-in reverses into a fade-out instead of being dropped.

### Added
- Short picture ease on the same ramp as the audio (`video_transition`, default
  `soft`): a mid-fade dim, plus a blur on `gpu` and `gpu-next`. The paused
  frame is sharp again unless `video_hold=yes`.
- `fade_curve=logarithmic` for an eased decibel ramp. `fade_curve=linear` keeps
  a straight ramp. `logarithmic_fade=no` still selects linear when
  `fade_curve=auto`.
- Unit tests (`lua5.4 tests/run_unit.lua`) and headless mpv checks
  (`tests/run_integration.sh`).

### Changed
- Default `fade_in_duration` is 0.45s, matching fade-out, so unpause is not a
  shorter, steeper ramp.

### Planned
- Per-file configuration support
- AUR package
- Homebrew formula

## [1.0.0] - 2025-10-23

### Added
- Initial public release
- Smooth audio fade-out when pausing (configurable duration, default 0.45s)
- Smooth audio fade-in when unpausing (configurable duration, default 0.3s)
- Logarithmic fade curve for natural-sounding transitions
- Linear fade curve option for constant-rate fading
- Configurable step count for fade smoothness (default 12 steps)
- MPRIS integration support (works with media keys and external controls)
- Debug mode with detailed logging for troubleshooting
- Configuration validation with automatic clamping to valid ranges
- Playback position preservation through pause cycles
- Zero-configuration operation with sensible defaults
- Configuration file support (`~/.config/mpv/script-opts/gradual_pause.conf`)
- Command-line option override via `--script-opts`
- Forced key binding for `space` and `p` keys
- Pause property observation for external pause triggers
- Proper cleanup on file change and player shutdown
- State management to prevent conflicts from simultaneous pause events
- Comprehensive README with installation and usage instructions
- MIT license
- Contributing guidelines
- GitHub issue and PR templates
- Example MPV configuration file
- Nix package definition for nixpkgs integration

### Technical Details
- Lua implementation using MPV's scripting API
- Periodic timer-based volume stepping
- Smart state flags to prevent reentrancy issues
- Volume restoration after fading to prevent persistence
- Position saving/restoration for seamless playback continuation

[unreleased]: https://github.com/gui-wf/mpv-gradual-pause/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/gui-wf/mpv-gradual-pause/releases/tag/v1.0.0
