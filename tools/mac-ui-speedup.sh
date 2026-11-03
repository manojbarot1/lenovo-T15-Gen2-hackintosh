#!/bin/bash
# Run on the T15 macOS as the logged-in user (no sudo): cut animations and transparency,
# which the unaccelerated Iris Xe framebuffer draws slowly.
#   ssh ... manojb@192.168.1.17 'bash -s' < tools/mac-ui-speedup.sh
set -u
w() { defaults write "$@" && echo "ok   $*" || echo "FAIL $*"; }

# Accessibility: Reduce motion / Reduce transparency (may need Full Disk Access; else set in System Settings)
w com.apple.universalaccess reduceMotion -bool true
w com.apple.universalaccess reduceTransparency -bool true

# Window and app animations
w NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
w NSGlobalDomain NSWindowResizeTime -float 0.001
w NSGlobalDomain NSScrollAnimationEnabled -bool false
w NSGlobalDomain QLPanelAnimationDuration -float 0
w com.apple.finder DisableAllAnimations -bool true

# Dock: no launch bounce, fast minimize, instant Mission Control
w com.apple.dock launchanim -bool false
w com.apple.dock mineffect -string scale
w com.apple.dock expose-animation-duration -float 0.1
w com.apple.dock autohide-delay -float 0
w com.apple.dock autohide-time-modifier -float 0.2

killall Dock Finder 2>/dev/null
echo "--- load and top CPU:"
uptime
ps -Ao pcpu,comm -r | head -6
