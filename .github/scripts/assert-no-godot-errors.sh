#!/usr/bin/env bash
# Fails if a Godot log contains errors caused by the project itself.
#
# Two things make this trickier than a plain grep:
#   * Godot exits 0 even when scripts fail to parse, so the log is the only
#     reliable signal.
#   * Progress lines carry ANSI colour codes even when stdout is not a TTY.
#
# CI machines have no GPU and no sound card, so Godot reports Vulkan and ALSA
# failures before falling back to OpenGL and the dummy audio driver. Those are
# environmental and must not fail the build, so generic "ERROR:" lines are
# matched against an ignore list; script and resource errors always fail.
#
# Usage: assert-no-godot-errors.sh <logfile> <description>
set -uo pipefail

log="${1:?usage: assert-no-godot-errors.sh <logfile> <description>}"
what="${2:-running Godot}"

if [ ! -f "$log" ]; then
	echo "::error::Expected log file '$log' was not produced while $what"
	exit 1
fi

# Errors that always mean the project is broken.
FATAL='SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|Failed to instantiate|Cannot instantiate|No loader found|Failed loading resource|Resource file not found|Invalid call|Attempt to call|Invalid get index|Invalid set index|Nonexistent function'

# Environment noise on headless / virtual-display runners.
BENIGN='Vulkan|VK_KHR|ALSA|alsa|audio_driver|AudioDriver|audio_server|V-Sync|vsync|DisplayServer|display_server|OpenGL|Mesa|llvmpipe|drivers/vulkan|drivers/alsa|drivers/pulseaudio|platform/linuxbsd|XOpenDisplay|X11|pulse|CADisplayLink|rendering_context|GLManager|gl_manager'

clean="$(mktemp)"
trap 'rm -f "$clean"' EXIT
sed -r 's/\x1b\[[0-9;]*[a-zA-Z]//g' "$log" >"$clean"

failed=0

if grep -qE "$FATAL" "$clean"; then
	echo "::error::Godot reported project errors while $what"
	grep -nE "$FATAL" "$clean" | head -40
	failed=1
fi

# Generic "ERROR:" lines: report only when neither the message nor its
# trailing "at: <source>" line looks like driver/audio fallback noise.
unexpected="$(
	awk -v benign="$BENIGN" '
		{ line[NR] = $0 }
		END {
			for (i = 1; i <= NR; i++) {
				if (line[i] !~ /^ERROR:/) continue
				context = line[i] " " (i < NR ? line[i + 1] : "")
				if (context !~ benign) print i ": " line[i]
			}
		}
	' "$clean"
)"

if [ -n "$unexpected" ]; then
	echo "::error::Godot reported unexpected errors while $what"
	printf '%s\n' "$unexpected" | head -40
	failed=1
fi

if [ "$failed" -ne 0 ]; then
	exit 1
fi

echo "No project errors while $what."
