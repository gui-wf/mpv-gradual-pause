# Contributing to MPV Gradual Pause

Thank you for your interest in contributing to mpv-gradual-pause! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Submitting Changes](#submitting-changes)
- [Reporting Bugs](#reporting-bugs)
- [Suggesting Enhancements](#suggesting-enhancements)

## Code of Conduct

This project aims to foster an open and welcoming environment. Please be respectful and constructive in all interactions.

### Our Standards

- **Be respectful**: Value diverse perspectives and experiences
- **Be constructive**: Provide actionable feedback and suggestions
- **Be collaborative**: Work together to improve the project
- **Be patient**: Remember that contributors have varying levels of experience

## How Can I Contribute?

### Reporting Bugs

Before creating a bug report, please check existing issues to avoid duplicates. When reporting bugs, include:

1. **MPV version**: Output of `mpv --version`
2. **Operating system**: Distribution/version (e.g., NixOS 24.11, Ubuntu 24.04, macOS 14.2)
3. **Audio backend**: Your `--ao` setting (pulse, pipewire, alsa, etc.)
4. **Script configuration**: Contents of `~/.config/mpv/script-opts/gradual_pause.conf`
5. **Debug log**: Enable `debug_mode=yes` and include console output (press `` ` `` in MPV)
6. **Steps to reproduce**: Clear, minimal steps to trigger the issue
7. **Expected behavior**: What should happen
8. **Actual behavior**: What actually happens

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When suggesting enhancements:

1. **Use a clear title**: Summarize the enhancement in one line
2. **Describe the use case**: Explain the problem this solves
3. **Describe the proposed solution**: How should it work?
4. **Consider alternatives**: What else could solve this problem?
5. **Provide examples**: Show how users would interact with the feature

### Pull Requests

We actively welcome pull requests for:

- Bug fixes
- Documentation improvements
- New features (please discuss in an issue first for major changes)
- Performance optimizations
- Test coverage improvements

## Development Setup

### Prerequisites

- **MPV**: Version 0.35.0 or later
- **Git**: For version control
- **Text editor**: Any editor with Lua syntax highlighting
- **Nix** (optional): For testing the Nix package build

### Local Development

1. **Fork and clone the repository**:
   ```bash
   git clone https://github.com/YOUR-USERNAME/mpv-gradual-pause.git
   cd mpv-gradual-pause
   ```

2. **Test the script locally**:
   ```bash
   # Run MPV with the development script
   mpv --script=./scripts/gradual_pause.lua \
        --script-opts=gradual_pause-debug_mode=yes \
        test-video.mp4
   ```

3. **Make changes**:
   - Edit `scripts/gradual_pause.lua`
   - Update documentation if needed
   - Test your changes thoroughly

4. **Test with different configurations**:
   ```bash
   # Test with different fade durations
   mpv --script=./scripts/gradual_pause.lua \
        --script-opts=gradual_pause-fade_out_duration=1.0 \
        video.mp4

   # Test with linear fading
   mpv --script=./scripts/gradual_pause.lua \
        --script-opts=gradual_pause-logarithmic_fade=no \
        video.mp4
   ```

### Testing the Nix Package

If you're modifying the Nix package definition:

```bash
# Build the package locally
nix-build -E 'with import <nixpkgs> {}; callPackage ./nix/package.nix {}'

# Test in a Nix shell
nix-shell -p '(callPackage ./nix/package.nix {})'

# If using flakes
nix build .#gradual-pause
```

## Coding Standards

### Lua Style Guide

- **Indentation**: 4 spaces (no tabs)
- **Line length**: Maximum 100 characters (120 for long strings/comments)
- **Naming conventions**:
  - Functions: `snake_case` (e.g., `fade_out_and_pause`)
  - Variables: `snake_case` (e.g., `original_volume`)
  - Constants: `UPPER_SNAKE_CASE` (if needed)
- **Comments**:
  - Use `--` for single-line comments
  - Document complex logic and non-obvious behavior
  - Add function docstrings for public functions
- **Error handling**: Validate inputs and handle edge cases gracefully

### Example Code Style

```lua
-- Good: Clear function name, proper spacing, documented logic
function calculate_fade_volume(step, total_steps, is_fade_out)
    -- Calculate linear volume based on current step
    local linear_volume = original_volume * (step / total_steps)

    -- Apply logarithmic adjustment if enabled
    if opts.logarithmic_fade then
        return apply_logarithmic_curve(linear_volume, is_fade_out)
    end

    return linear_volume
end

-- Bad: Poor naming, cramped spacing, no comments
function calc(s,t,f)
local v=orig_vol*(s/t)
if opts.log then return log_adj(v,f) end
return v
end
```

### Commit Messages

Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, no logic changes)
- `refactor`: Code refactoring (no functional changes)
- `test`: Adding or updating tests
- `chore`: Maintenance tasks (dependencies, build process)

**Examples**:
```
feat: add configurable fade curve types

Adds support for exponential and sine-wave fade curves in addition
to the existing linear and logarithmic options.

Closes #42
```

```
fix: prevent volume overflow when steps < 5

When step count is very low, volume could exceed original_volume
during fade-in. Added bounds checking to clamp values.
```

```
docs: improve troubleshooting section in README

Added common issue about MPRIS conflicts and how to debug them.
```

## Submitting Changes

### Pull Request Process

1. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**:
   - Write clear, focused commits
   - Follow coding standards
   - Update documentation if needed

3. **Test thoroughly**:
   - Test with default configuration
   - Test with various custom configurations
   - Test on different MPV versions if possible
   - Verify debug mode works correctly

4. **Update documentation**:
   - Update README.md if adding features or changing behavior
   - Update CHANGELOG.md with your changes
   - Add inline comments for complex logic

5. **Push to your fork**:
   ```bash
   git push origin feature/your-feature-name
   ```

6. **Open a pull request**:
   - Use a clear, descriptive title
   - Describe what changed and why
   - Link related issues (e.g., "Fixes #123")
   - Include testing steps

### PR Review Process

- **Automated checks**: PRs may run automated tests (if configured)
- **Maintainer review**: A maintainer will review your code
- **Feedback**: Address any requested changes
- **Approval**: Once approved, your PR will be merged

### After Your PR is Merged

- **Delete your branch**: Clean up your local and remote branches
- **Update your fork**: Pull the latest changes from upstream
- **Celebrate**: You've contributed to open source! 🎉

## Reporting Security Issues

If you discover a security vulnerability, please email the maintainer directly instead of opening a public issue:

- **Email**: 48162143+gui-wf@users.noreply.github.com

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if you have one)

## Questions?

If you have questions about contributing:

1. Check existing issues and discussions
2. Open a new issue with the `question` label
3. Reach out to the maintainer

## Attribution

By contributing to this project, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to mpv-gradual-pause! Your efforts help make MPV better for everyone.
