# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Exponential and sine-wave fade curve options
- Per-file configuration support
- Integration tests
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
