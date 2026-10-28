# Stand-In design system

One product, every platform. A screen on the desktop client and the same screen on
Android must be indistinguishable apart from the window chrome the OS draws. When a
platform can't do something the same way, it fakes it until it looks the same; it
never falls back to its stock look.

Values live in `tokens.json`; `generate.py` turns them into each platform's theme.
Never hard-code a color, size or font in a screen. If a value is missing, add a token.

## Principles

1. **One obvious next step.** Every screen has at most one primary (teal) button.
   Everything else is secondary, an icon button, or tucked into a "more" menu.
2. **Say what will happen, in plain words.** "Connect", "Wake and connect", "Take over".
   No jargon (no "host", "stream", "GFE", "applist", "bitrate" outside Settings > Advanced).
   Pairing is "wants to pair", never "wants to connect".
3. **Quiet surfaces, one accent.** Flat panels separated by 1px borders, no shadows
   except dialogs. Teal only marks the primary action, the selection, focus and
   "awake/on". Amber means needs attention. Red only for destructive or failed.
4. **Works from a couch.** Everything is reachable with a gamepad or arrow keys. Focus
   is always visible (2px accent-hover ring) and moves in the direction pressed.
5. **Calm motion.** 120ms for state changes, 180ms for menus/dialogs, 220ms for page
   changes (fade + 16px slide). Nothing bounces.

## Foundations

**Color** (Midnight Slate, default theme)

| Token | Use |
|---|---|
| ground `#12161C` | window / page background |
| surface `#1A2029` | cards, dialogs, groups |
| raised `#222A35` | pills, selected tiles, input fields, hover on surface |
| border `#2C3542` | 1px outlines and separators |
| borderStrong `#3A4554` | dashed "add" outlines, input outline |
| text `#E6EAF0` | primary text, icons |
| muted `#98A2B3` | secondary text, section labels |
| subtle `#6B7686` | tertiary text, disabled, offline |
| accent `#2DD4BF` | primary button, switches on, selection, awake |
| accentHover `#5EEAD4` | hover/pressed primary, focus ring |
| onAccent `#04201C` | text on accent |
| warning `#F5A524` / warningSoft | needs attention; banners use the soft fill |
| danger `#F87171` / dangerSoft | errors, Remove |

Other themes (Settings > Appearance) only swap these values; layouts never change.

**Type**: Inter, bundled with every client (never the platform font).

| Style | Size/weight | Use |
|---|---|---|
| display | 26 bold | PC name in the hero card |
| title | 20 semibold | page titles, dialog titles |
| headline | 17 semibold | product name in the header, group titles |
| body | 15 regular | paragraphs, row subtitles in dialogs |
| bodyStrong | 15 semibold | row titles, tile names |
| button | 15 semibold | all buttons |
| label | 13 medium | section labels ("Your PCs"), row subtitles |
| caption | 12 regular | status lines, metadata, version pill |

Sentence case everywhere. No ALL CAPS, no Title Case On Buttons.

**Space**: 4, 8, 12, 16, 24, 32, 40. Page gutter 24. Content column max 720, centered.

**Radius**: xs 8 (small pills), sm 12 (icon buttons, inputs, menu rows), md 16 (tiles,
popup menus), lg 22 (cards, groups), xl 28 (dialogs). Buttons are capsules (height/2).

**Icons**: `../icons/*.svg`, 24 grid, 1.5 stroke, round caps and joins, drawn in `text`
and tinted per use. Shown at 22 (icon) or 18 (iconSmall). No filled or Material icons.

**Focus**: 2px `accentHover` ring that follows the control's shape, inset 0. Hover (pointer only)
lightens surface → raised. Pressed darkens accent → accentHover for primary.

## Components

**Header** (height 56, gutter 24): left: logo 28 (the app icon) + "Stand-In" (headline)
+ version pill. Right: icon buttons, in this order: Devices (usb), Settings (gear).
Sub-pages replace the left side with a back icon button + page title (title style);
the right side keeps only actions that belong to that page.

**Version pill**: raised fill, 1px border, radius xs*1.6 (13), height 24, padding 10,
caption muted, text "Beta 2 · 0.2.0".

**Icon button**: 44×44, radius sm, surface fill, 1px border, icon 22 in `text`.
Hover: raised. Focus: ring.

**Primary button**: capsule, height 44 (48 in the hero card), accent fill, onAccent
button text, horizontal padding 24, min width 120 (hero: 220). Hover/pressed: accentHover.
Disabled: raised fill, subtle text.

**Secondary button**: capsule, height 44, raised fill, 1px border, text color text.
**Destructive button**: secondary with danger text. Used only in confirmations.
**Text button**: no fill, accent text; only for low-stakes inline links ("Add PC manually").

**Card**: surface fill, 1px border, radius lg, padding 24.

**Hero card** (home): card, 720 wide, centered contents: PC icon 48 (tower), 8 gap,
PC name (display), 2 gap, status line (body muted, "Awake · Ready to connect"),
16 gap, primary button 220×48. A 44 "more" icon button sits in the card's top-right
corner (12 inset) and opens the PC menu.

**PC tile**: 112×96, radius md, padding 12, surface + border; selected (the PC in the
hero card): raised + 2px accent border. Top: tower icon 22. Bottom: name (bodyStrong,
one line, ellipsis) and status row (8 dot + 6 gap + caption muted).
**Add tile**: same size, transparent, 1px dashed borderStrong (6 dash, 4 gap),
centered plus icon 22 + "Add PC" caption muted.
Tiles sit in one row with 12 gaps, scrolling sideways when they don't fit; the add tile
is always last and always visible.

**Status dot + text**: Awake (accent) "Awake", Asleep (muted) "Asleep", Not paired
(warning) "Not paired", In use (warning) "In use by <client>", Offline (subtle) "Offline",
Checking (spinner 12) "Checking…".

**Section label**: label style, muted, 8 below / 24 above, aligned to the content column.

**Group**: card with padding 0 holding rows; 1px border separators between rows,
inset 16 from the left. Groups stack with 24 between (section label above each).

**Row**: min height 56 (68 with subtitle), padding 16 horizontal. Optional leading
icon in a 36 circle (raised fill, icon 18 muted). Title bodyStrong; subtitle label muted,
up to 2 lines. Trailing, one of: switch, value text (body muted) + chevron-right,
chevron alone, a secondary button. The whole row is the click/focus target; focus ring
follows the group shape for the first and last rows.

**Switch**: 44×26 track, capsule. Off: raised track + 1px borderStrong, thumb 20 muted.
On: accent track, thumb onAccent. 120ms slide.

**Choice picker**: tapping a value row opens a popup menu anchored to the row
(or a dialog with a radio list when there are more than 8 options). Selected
item shows a check icon in accent.

**Slider row**: title + current value (body, right), slider below: 4px raised track,
accent fill, 20 thumb in text color.

**Input**: height 48, radius sm, raised fill, 1px borderStrong; focus: 2px accent.
Placeholder subtle, text body. Label above in label muted.

**Popup menu**: surface, 1px border, radius md, padding 6, shadow 0 12 32 #66000000.
Rows height 44, radius sm, padding 12, body text, optional leading icon 18.
Destructive rows use danger text. Hover/focus: raised fill.

**Dialog**: scrim; panel width 440 (max 90% of the window), surface, 1px border,
radius xl, padding 28. Title (title), 8 gap, body (body muted), 24 gap, content,
24 gap, buttons right-aligned with 12 gap: secondary then primary. Escape/Back = cancel.

**Banner**: radius md, padding 16, warningSoft fill + 1px warning at 30% alpha,
warning icon 18 + body text; may hold a copyable command (monospace caption in raised
box) or a text button.

**Empty state**: centered icon 48 muted, title, body muted, one button.

**Spinner**: 2px accent arc, 20 (inline 12, hero 48).

## Screens

### Home
Header (logo, Devices, Settings). "Your PCs". Hero card for the last-used awake PC
(else the first paired PC, else the first PC). Tile row under it, gap 12.

Hero button per state: Awake → **Connect**; Asleep → **Wake and connect**;
Not paired → **Pair**; In use → **Take over**; Offline → no button, status
"Offline · Last seen …" if known; Checking → spinner, no button.
Hero "more" menu: All apps, Wake (asleep only), Rename, Test network, Remove (danger, confirms).
No PCs at all: hero becomes an empty state: spinner "Looking for your PCs…",
body "Stand-In finds PCs on your network and on Tailscale.", text button "Add PC manually".

### Add PC (dialog)
Title "Add a PC". Body "Enter the PC's name or IP address. It needs Stand-In Server
running." Input (placeholder "e.g. big-pc or 192.168.1.20"). Buttons: Cancel, **Add**.
While adding: Add shows a spinner and the input locks. Errors appear under the input
in danger caption, in plain words ("Couldn't reach big-pc. Check that it's on and
Stand-In Server is running.").

### Pair (dialog)
Title "Pair with <PC>". Body "On <PC>, open Stand-In from the tray and enter this code."
Code: 4 digits, each in a 56×64 raised box, radius sm, 32 bold, 8 gap, centered.
Status line under it (caption muted): "Waiting for <PC>…" with spinner.
Buttons: Cancel. Success closes the dialog and the hero button becomes Connect.

### Message / error (dialog)
Title states what happened ("Couldn't connect to <PC>"). Body is the server's own
message when there is one, then one sentence on what to try. Buttons: optional
secondary ("Details" opens the technical text), **OK**.

### Connecting
Full window ground. Centered: spinner 48, "Connecting to <PC>…" (title), status
line (label muted: "Setting up your screens"), secondary **Cancel** button.

### Settings
Header: back + "Settings".
Wide windows (≥ 760 wide): two panes. Left: sidebar 220 wide, list of categories
(rows height 44, radius sm, icon 18 + label; selected = raised fill + accent icon).
Right: the category's groups in a scrolling column (max 560).
Narrow windows: the category list is the page; picking one pushes its page.

Categories, in order (icon):
1. Display & quality (display): Resolution, Frame rate, Quality, Show performance stats.
   All three start on **Automatic** (see "It just works" below).
2. Audio (speaker): Sound output (Stereo / 5.1 / 7.1), Play sound on the PC too, Mute when in background.
3. Input (keyboard): Touch works like (a trackpad / direct touch), Mouse, Keyboard shortcuts.
4. Controllers (gamepad): controller options; On-screen controls (touch platforms).
5. Devices (usb): link row "USB devices" → Devices page; "Send devices automatically".
6. Appearance (palette): Theme (swatch row), Show the version tag.
7. Advanced (sliders): everything technical (codec, frame pacing, HDR, network options…),
   each with a one-line plain explanation.
8. About (info): version, "Built on Moonlight, Artemis and Apollo" credits with licences, source link.

**It just works.** Install, pair, Connect: nothing needs setting first.
- Resolution: first option "Automatic", default. Subtitle "Matches this screen (W × H)."
  Streams at the native resolution of the screen the client is on, read when connecting.
  Then fixed sizes (720p, 1080p, 1440p, 4K, other screens), "Custom…".
- Frame rate: first option "Automatic", default. Subtitle "Matches this screen (N FPS)."
  Uses that screen's refresh rate. Then 30/60/90/120…, "Custom…".
- Quality: Automatic (default) / Manual. Automatic subtitle "Adjusts to your network
  while you use it." The client asks for the default bitrate for the resolution and frame
  rate it streams at; the server starts at what held up last time on this network and
  lowers or raises it while streaming. Manual shows the Bitrate slider, subtitle "Stays at
  the bitrate you set. Lower it if the picture stutters.", and the server never changes it.
- Protocol: Stand-In clients add `autoBitrate=1|0` to the launch/resume query. Missing
  (stock Moonlight) means 1.
- Picking a fixed size, rate or Custom turns that one setting's Automatic off; picking
  Automatic turns it back on.

Platform-only options appear only where they work, in the same category and group
shape; they never change the layout of the options both platforms share.

### Devices
Header: back + "Devices". Under it, a group with one row: "Send to" + value (PC name)
+ chevron → picker; trailing status dot (Online/Offline).
Body text (label muted): "A device that's switched on is unplugged from this machine and
plugged into your PC. Use it for wheels, flight sticks, pedals, drawing tablets and
anything that needs its own driver on the PC."
Optional permission banner (Linux): text + copyable command.
"On this machine" section label, then one group of device rows: leading 36 circle with the
kind icon (gamepad input, drive storage, speaker audio, camera video, bluetooth wireless,
globe network, flask test, usb other), title = device name, subtitle = maker · ids,
status line under it in caption: accent "Plugged into <PC>", warning "Couldn't send it: …",
muted otherwise. Trailing switch. Devices that can't be sent show the switch disabled and
say why. Unplugged-but-remembered devices show "Not plugged in · it'll be sent when it is".
Platforms that can't send yet show the page with the switch disabled and the banner
"Sending USB devices from <platform> is coming soon."

### All apps
Header: back + PC name. Grid of app cards (box art 3:4, radius md, name under it in
bodyStrong). Focused card scales 1.04 with focus ring. "Desktop" is always first.
