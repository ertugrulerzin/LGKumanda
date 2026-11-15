---
name: LG Kumanda
description: A light native iPhone remote with tactile controls and ergonomic text entry.
colors:
  primary: "rgb(148, 31, 69)"
  background: "#f2f2f7"
  surface: "#ffffff"
  label: "#000000"
rounded:
  control: "16pt"
  rocker: "20pt"
spacing:
  gap: "12pt"
  inset: "20pt"
  group: "22pt"
components:
  remote-button:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.label}"
    rounded: "{rounded.control}"
    height: "56pt minimum"
  primary-button:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.surface}"
    rounded: "{rounded.control}"
---

## Overview

**Creative North Star: "A quiet remote within reach."**

A native iPhone tool for operating a television. The user's confirmed light appearance governs the app. Spacious neutral surfaces, precise SF Symbols and restrained burgundy accents give the central OK action and text send action a clear visual anchor. The native platform governs navigation and typography.

## Colors

The primary accent belongs to active controls and selection. Background and surface values describe the light rendering; implementation uses UIKit semantic grouped colors. Native secondary labels carry supporting instructions. Connection status has both a symbol or dot and a text label.

**The Light Surface Rule.** Keep the user-selected light appearance even when the phone uses dark appearance. A future appearance setting would be a product change.

## Typography

San Francisco uses SwiftUI semantic text styles and Dynamic Type. Native large titles label top-level lists and the remote. The keyboard uses an inline title to preserve space above the software keyboard. Body is the standard input size; captions identify secondary controls. Numeric volume uses tabular figures.

## Layout

Five native tabs: remote, apps, channels, keyboard, devices. Navigation stacks own titles. Lists and forms use system grouping. Remote content has a maximum width of 520pt and scrolls on shorter phones. Volume and channel rockers flank the direction pad; ViewThatFits chooses a smaller pad when needed.

**The Keyboard Reach Rule.** Compose and send live in a bottom safe-area inset immediately above the software keyboard. TV Enter, delete and keyboard visibility stay next to that input. The touch area stays above it; supplemental instructions disappear while typing. Accessibility text sizes increase the focused touch area height, and the body remains scrollable.

## Elevation & Depth

The application draws no custom shadows. White controls stand above the grouped background through tonal separation. Native tab bars, sheets, menus and keyboard supply platform materials and elevation.

## Shapes

Remote keys use gently rounded rectangles, while OK sits inside a circular directional pad. Volume and channel rockers are vertically elongated surfaces. Pointer input uses a rounded rectangular working area. Send is a circle with a single SF arrow.

## Components

Remote buttons have a minimum 56pt height, haptic feedback when enabled, and visibly dim when disabled. Pressed feedback changes opacity. Directional targets exceed the native 44pt minimum on the supported phone layouts.

Pointer mode is a native segmented control: **İşaretçisiz** sends arrow/OK commands; **Fare** sends relative pointer movement, click and scroll. Pointer sensitivity uses a native slider. All explanations use Turkish copy.

Network discovery uses a native progress bar, a stop action, and a Settings action when local-network access is denied. Device setup uses a native form. Errors remain beside the relevant input or appear as an app alert. Keyboard failures preserve typed text. Connections expose disconnected, connecting, pairing and connected states.

## Do's and Don'ts

- Do use SF Symbols and native semantic text styles.
- Do keep the keyboard composer in the safe area.
- Do distinguish unsupported pointer input from a working TV connection.
- Don't introduce a cursor movement into cursorless navigation.
- Don't imply that a successful pairing proves every model-specific command works.
