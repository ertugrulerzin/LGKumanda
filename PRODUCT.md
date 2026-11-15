# LG Kumanda

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack
SwiftUI, native iPhone app. Implementation choice inferred from the request for an iPhone app.

## Users
Turkish-speaking LG TV owner operating a television from an iPhone.

## Product Purpose
Provide the functions of an LG remote, within the capabilities exposed by the TV's local webOS API.

## Operating Context
Phone and TV on the same local network; pairing approved on the TV. Discovered and paired TV: LG OLED55C64LA. User approved the pairing prompt on the physical TV.

## Capabilities and Constraints
Remote buttons, directional navigation, volume, channel, playback, numeric and colored keys, input selection, installed apps, text input, pointer input, Wake-on-LAN. Support depends on firmware. Read-only integration verified from the iPhone simulator against the physical TV: saved TLS pairing, volume read, pointer socket, SSDP, 23 apps, 4 inputs, 644 channels. Individual state-changing commands and installation on a physical iPhone remain unverified. No proprietary voice assistant emulation.

## Brand Commitments
User selected a light interface. Turkish copy. LG Kumanda is a descriptive working name; not an official LG product.

## Keyboard and Pointer Priorities
User explicitly prioritizes keyboard ergonomics and mouse use. Their cat jumps at the cursor on the TV. Provide a cursorless touch navigation mode using arrow/OK keys, alongside real pointer control. Keep text entry and its send/enter/delete controls near the iPhone keyboard; preserve drafts on failure.

## Product Principles
- Make common controls reachable with one hand.
- Show connection and command failures honestly.
- Store pairing credentials in Keychain.
- Keep TV communication on the local network.

## Discovery reliability
Build 1 used SSDP multicast without the restricted iPhone entitlement; the user reported that TV search failed in TestFlight. Build 2 adds bounded HTTP identification on the current Wi-Fi subnet, validates LG/webOS device descriptions, deduplicates Wi-Fi/Ethernet interfaces using UDN and prefers saved addresses. It detects explicit local-network permission failures and offers Settings. Direct discovery was verified with multicast disabled against the physical TV from the iPhone simulator. A physical-iPhone retest is still required.

## Home shortcuts and platform controls
The user requests configurable home shortcuts for Netflix, YouTube, browser and both HDMI/native TV platforms. The actual TV reports Tivibu on HDMI 3 and TVP on HDMI 4, plus a native TV+ app. Use real app/input IDs, persist shortcuts separately for each saved TV, and allow renaming/reordering. Route channel/playback keys according to the foreground app; do not force the TV tuner while a platform is active. HDMI-box response depends on CEC/IR support and remains unverified. The user has not tested the LG physical remote against the box yet.

The user additionally prioritizes direct iPhone-keyboard URL entry when opening the TV browser. Provide an automatically focused URL composer with paste and TV-open actions; do not require selecting the TV address bar with a pointer. No persistent phone URL history is introduced.

## Build 1.0 (4): SIMPLINK visibility and Google search
User reported that direction keys do not reach Tivibu. The TV's input list (2026-11-15) shows no SIMPLINK device on HDMI 3 ("tivibu"); the only CEC device, OSD name "Tivibu Android", is on HDMI 4 ("tvp"). Network keys can only reach a box that the TV lists under SIMPLINK, so the app now warns when the active HDMI input has none and lists each input's SIMPLINK device in HDMI help. The browser composer treats text that is not an address as a Google search (iPhone web-search keyboard, so spaces are available).

## Build 1.0 (5): pointer in the web browser
In pointerless mode the touch pad only sends arrow keys. The LG browser does not move between links with arrow keys, so links never highlight. While the browser is in the foreground the touch pad now drives the real pointer by default ("Web'de fare kullan", can be turned off). Elsewhere the user's pointerless choice still applies, and HDMI inputs always stay pointerless.

## Build 1.0 (6): quiet pointer
The cat still chased the gliding cursor in browser mouse mode. Quiet pointer (default on in mouse mode) buffers the drag and moves the pointer in one jump on finger lift, so nothing glides across the screen. Jumps are sent as back-to-back ±32 moves, bounded to about one screen.

## Build 1.0 (7): pick links on the phone
The user wants web browsing that behaves like YouTube or the LG home menu, with no pointer on the TV. The LG browser has no arrow-key focus between links, so the user chose phone-side link picking. After the address screen opens a page on the TV, the same page opens in a phone web view (non-persistent data). Every page the user then opens on the phone is opened in the TV browser; up/down buttons scroll the TV page with arrow keys. The browser touch pad now defaults to pointerless (setting key renamed to browserUsesPointerV2 so the new default applies), and the quiet-pointer jump gain dropped from 2.5x to 0.8x.

## Build 1.0 (8): Cloudflare check on the TV
Sites behind Cloudflare challenge the TV browser even when the phone already passed; cookies are not shared, so this cannot be bypassed. The phone page now has a cursor button that opens a temporary mouse pad (forced pointer mode) to tick the box on the TV once, then returns to pointerless browsing.

## Build 1.0 (9): video plays on the TV
Playing a video on the phone page only played it on the phone, because in-page actions are not mirrored, only page changes. The phone web view now pauses and mutes any media in all frames on its play event and opens the TV touch pad with a "play on the TV" hint, so the user presses play on the TV.

## Build 1.0 (10): AirPlay for web video
On Filmakinesi the TV touch pad opened but the TV browser could not play the video; such players often fail in the LG browser. Playing a video on the phone now offers AirPlay (system route picker, video devices first). Choosing it rebuilds the phone page without the media blocker so the phone plays and iOS routes the video to the LG TV. The TV-browser pointer path remains as the second option.

Build 1.0 (10) AirPlay was rejected by the user: the app will also be written for Android, so web video must not depend on an iOS-only path. Removed in the next build; behaviour is back to 1.0 (9).

## Build 1.0 (11): reaching the play button
Live test on the TV browser (Mac-hosted page with a cross-origin iframe): the app's `type:click` arrives as a real pointerdown/mousedown/mouseup/click, also after the pointer auto-hides and after a burst jump; ENTER gives a key click. The user could not get the pointer onto the play button, so the TV pad sheet now follows the finger (quiet jump off there), adds repeatable nudge arrows (4 units ≈ 13 px; one move unit ≈ 3 screen px on this TV) and a large Click button. AirPlay removed.
