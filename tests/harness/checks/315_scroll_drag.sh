#!/usr/bin/env bash
# A modified middle-button bind pans the scrolling layout continuously and settles it through the same path as a
# three-finger gesture. In overview, an unmodified middle drag steps workspace rows while a stationary middle click
# remains the close gesture; delaying close until release lets motion disambiguate the two without swallowing ordinary
# middle clicks outside the overview.
set -euo pipefail

readonly OUTPUT_W=1280
readonly OUTPUT_H=720
readonly BTN_MIDDLE=274
readonly POINTER="${UMBRIEL_POINTER_CLIENT:-./build-debug/pointer-client}"
readonly WORKSPACE="${UMBRIEL_WORKSPACE_CLIENT:-./build-debug/workspace-client}"

cat >> "$UMBRIEL_CONFIG" <<'EOF'

[animation]
enabled = false

[layout.scrolling]
default_width_fraction = 0.5

[keybinds]
"Mod+MouseMiddle" = "layout-scroll-drag"
EOF
"$UMBRIEL" msg config-reload > /dev/null

pointer() {
  "$POINTER" "$OUTPUT_W" "$OUTPUT_H" "$@"
}

window_count() {
  "$UMBRIEL" windows --json | jq 'length'
}

wait_for_count() {
  for _ in $(seq 80); do
    [[ $(window_count) -eq $1 ]] && return 0
    sleep 0.25
  done
  echo "timed out waiting for $1 windows, have $(window_count)"
  return 1
}

count=0
for title in A B C D; do
  foot --title="$title" sh -c 'sleep 120' > /dev/null 2>&1 &
  count=$((count + 1))
  wait_for_count "$count"
done

# New windows focus at strip end. Return to A so dragging left has room to pan.
for _ in 1 2 3; do
  "$UMBRIEL" msg window-focus-left > /dev/null
done
before_x=$("$UMBRIEL" windows --json | jq -r '.[] | select(.title == "A") | .x')

pointer move 900 360 mod logo press "$BTN_MIDDLE" move 850 360 move 350 360 release "$BTN_MIDDLE" mod none
after_x=$("$UMBRIEL" windows --json | jq -r '.[] | select(.title == "A") | .x')
if ((after_x >= before_x)); then
  echo "layout-scroll-drag did not pan toward strip end: A x $before_x -> $after_x"
  exit 1
fi

# The same physical button needs no modifier in overview. The first motion crosses the drag threshold; the second
# crosses one row step. Releasing after motion must not close the card under the original press.
pointer move 640 360
"$UMBRIEL" msg overview-open > /dev/null
pointer press "$BTN_MIDDLE" move 640 330 move 640 150 release "$BTN_MIDDLE"

for _ in $(seq 20); do
  [[ $("$WORKSPACE") == 2 ]] && break
  sleep 0.1
done
if [[ $("$WORKSPACE") != 2 ]]; then
  echo "overview middle drag did not select workspace 2"
  exit 1
fi
if [[ $(window_count) -ne 4 ]]; then
  echo "overview middle drag closed a card instead of navigating"
  exit 1
fi

# Return to the occupied row, then prove the click half of the gesture is
# deferred: the press alone leaves the card mapped and the matching release
# sends exactly one close request.
pointer press "$BTN_MIDDLE" move 640 180 move 640 360 release "$BTN_MIDDLE"
for _ in $(seq 20); do
  [[ $("$WORKSPACE") == 1 ]] && break
  sleep 0.1
done
pointer move 640 360 press "$BTN_MIDDLE"
if [[ $(window_count) -ne 4 ]]; then
  echo "overview middle press closed a card before release"
  exit 1
fi
pointer release "$BTN_MIDDLE"
wait_for_count 3

echo "mouse drag pans layouts, navigates overview rows, and preserves release-only middle-click close"
