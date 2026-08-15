# RetTwistHUD

A swing timer for TBC retribution paladins that lives around your character
instead of at the bottom of the screen, so you can twist seals without staring
at a bar below your feet.

Interface 20506 (TBC Anniversary).

## What it draws

One thin ring centred on your character. Nothing is drawn inside it, so your
model and the ground around you stay clear.

- A pip laps the ring once per weapon swing. It reaches the top exactly when
  the swing lands.
- The ring colour is your active seal. Gold means the carrier seal is up and a
  twist is pending. Crimson means the finisher is already up and this swing has
  nothing to twist.
- A green wedge just before the top is the twist window. It only appears when
  the twist is actually available.
- A dark segment ahead of the pip is your global cooldown. If it runs into the
  window, the window greys out and you know a swing early not to bother.
- A blue post crossing the ring is the last moment you can start a global
  cooldown spell and still have it clear before the twist window. It dims once
  the pip is past it, so bright means go ahead and dim means hold.

The post is a property of the swing and the global cooldown, not of your seal,
so it is drawn on every live swing whatever you are holding. Only the cost of
passing it changes: with Seal of Command up you lose a filler ability, with Seal
of Blood up you lose the chance to swap back and the twist goes with it, and
with any other seal it is the point your setup has to be finished by.
- A violet arc on an outer radius at the bottom is the Judgement cooldown. It
  shrinks toward the middle as the cooldown runs and vanishes when it is ready,
  so an empty bottom means Judgement is up.
- A teal arc is the Crusader Strike cooldown, behaving the same way. Where it
  sits is up to you, see below.
- An icon above your head is whichever seal you actually have up, with a thin
  ring around it counting down the seal's remaining duration.

Those two arcs plus the last safe cast post answer the whole question between
them: an empty arc means the ability is up, and a bright post means you can
still spend a global cooldown on it without losing the twist.

The window and the post are both drawn shifted back by your latency, because the
press has to leave your client one round trip before the server checks the seal.

## The seal icon

The ring's colour tells you the seal's twist role: gold for the carrier, rose
for the finisher, grey for anything else. That works for two seals and stops
working past that, so the icon is what actually identifies the seal.

Every paladin seal is tracked, not just the two you twist between. Seal of the
Crusader opens boss fights and is a seal like any other, so it shows its own
icon and it counts for the seal-aware visibility modes.

The icon sits above your head by default. `/rth sealangle N` moves it anywhere
around the ring, in degrees clockwise from the top, so 90 is the right side and
180 is straight down. Bottom placements will collide with the cooldown arcs.

Unlike everything else, the seal readout is never dimmed by the quiet setting.
Which seal is up is exactly what you want to know when nothing else is
happening, so it keeps full brightness at all times.

## Visibility

`/rth show MODE` picks when the ring exists at all.

| Mode | Shows |
| --- | --- |
| `always` | Permanently, even standing in a city. |
| `combat` | Only in combat. |
| `seal` | Only while Seal of Command or Seal of Blood is up. |
| `either` | In combat or with a seal up. The default. |
| `both` | In combat and with a seal up. |

`seal` counts any paladin seal, including Seal of the Crusader.

When the ring is visible but you are not actually swinging at anything, it holds
a quiet outline in your seal colour with no pip, no window and no ticks. That
tells you which seal is up while you run in, without anything moving to pull
your eye.

## Crusader Strike placement

Four layouts, all reachable from the options panel or `/rth csplace`.

| Mode | Layout |
| --- | --- |
| `stacked` | Second arc just outside Judgement. Both cooldowns in one glance zone, and Judgement's geometry is untouched. The default. |
| `mirrored` | Its own arc on the right of the ring. Position alone tells them apart, at the cost of a second place to look. |
| `split` | One bottom band divided at six o'clock, each half retracting toward the seam. One object, but half the resolution each. |
| `nested` | Inside the ring. Uses otherwise empty space, but can land on your feet at close camera distances. |

Crusader Strike defaults to a shorter span than Judgement so the two silhouettes
differ before colour resolves.

## Options panel

Left click the minimap button or type `/rth`; either toggles it. Escape closes
it and you can drag it by its background. Every setting in it is also a slash
command and the two stay in sync, so use whichever suits.

It is a window of its own rather than a page inside Blizzard's interface options
frame. That API has changed shape three times across the Classic re-releases and
fails silently when it does, which is exactly what happened the first time this
was wired up: registering the panel appeared to succeed and opening it did
nothing at all. Owning the window removes the entire class of problem.

The panel is still built inside a `pcall`. If a Blizzard widget template it
depends on is missing or has changed shape on your client, the panel fails on
its own and prints a message, and the ring and every slash command keep working.

## Minimap button

Left click opens the settings, right click unlocks the ring so you can drag it
into place, and dragging the button itself moves it around the minimap edge.
`/rth minimap off` hides it, or use the checkbox in the panel.

It is written out rather than pulled in from LibDBIcon. The addon has no other
dependencies and a minimap button is about a hundred lines, so vendoring four
library files to get one would cost more than it saves. Its icon is borrowed
from a spell the addon already looks up, so the art path cannot go stale.

## Commands

`/rth help` lists everything.

| Command | Effect |
| --- | --- |
| `/rth lock` | Toggle dragging. Unlocked also previews fake swings. |
| `/rth test` | Fake swings so you can position it out of combat. |
| `/rth radius N` | Distance from your character. Default 92. |
| `/rth thickness N` | Ring line weight. Default 5. |
| `/rth fill N` | 0.2 for a fine dotted ring, 1.0 for solid. Default 0.72. |
| `/rth track N` | Dark groove behind the ring, 0 to 1. Default 0.7. |
| `/rth trackpad N` | How far the groove sticks out, in px. Default 2. |
| `/rth quiet N` | Dim when no twist is pending. Default 0.6. |
| `/rth window N` | Twist window width in ms. Default 400. |
| `/rth latency N` | Press offset in ms, or `auto` to read it from the client. |
| `/rth safety N` | Window ms to keep free when placing the post. Default 150. |
| `/rth gcd on\|off` | Paint the current global cooldown on the ring. |
| `/rth lastsafe on\|off` | The last safe cast post. |
| `/rth judgement on\|off` | The Judgement cooldown arc. |
| `/rth crusader on\|off` | The Crusader Strike cooldown arc. |
| `/rth csplace MODE` | `stacked`, `mirrored`, `split` or `nested`. |
| `/rth seal on\|off` | The active seal icon. |
| `/rth sealduration on\|off` | The countdown ring around it. |
| `/rth sealangle N` | Where it sits, degrees clockwise from the top. |
| `/rth sealsize N` | Seal icon size. Default 26. |
| `/rth show MODE` | When the ring is visible. See below. |
| `/rth minimap on\|off` | Show the minimap button. |
| `/rth swap` | Swap which seal is the carrier and which is the finisher. |
| `/rth reset` | Restore every default. |

Defaults assume Seal of Command is the carrier and Seal of Blood is the
finisher. Run `/rth swap` if you twist the other way round.

## Tuning it

Two settings actually matter, and both are personal.

`window` is how long before impact a seal swap still counts. 400 ms is the
usual figure. Lower it if twists are landing but the second seal is stealing the
first one's proc.

`latency` shifts the whole window earlier to cover your round trip. `auto`
reads the client's world latency each swing, which is right most of the time.
If your twists consistently land a fraction late, add 20 to 40 ms manually.

`safety` decides how greedy the last safe cast post is. It is the amount of
window you insist on still having free after the global cooldown clears. At 0
the post sits at the absolute last possible instant and any jitter loses you the
twist. At 150 ms you keep a comfortable margin. Raise it if you find yourself
casting right on the post and missing.

The post is placed using the global cooldown length the addon has actually
observed, not a hardcoded 1.5 s, so it stays correct if that ever differs.

## Contrast

The ring has to stay readable over grass, lava, a lit floor and whatever a boss
puts under you. Three things do that work.

**The dark track.** Every element is drawn on a solid black groove slightly
larger than itself, so its contrast comes from the groove rather than from
whatever you happen to be standing in. `/rth track 0` removes it if you ever
want the ring bare, `/rth trackpad N` changes how far it sticks out. This is the
single setting that matters most on a busy floor.

**Brightness carries the signal, hue only labels it.** Peripheral vision is
close to colourblind, so the twist window is the brightest thing on the ring
rather than the greenest. If you find yourself relying on colour to spot the
window, something has gone wrong with the brightness ordering.

**Quiet states give their contrast back.** The ring dims to `quietAlpha` when
there is genuinely nothing to decide: you are not swinging, or you are holding
a seal you cannot twist from. Holding either twist seal is never quiet, even
when the window is dark, because there is always a call to make about your next
global cooldown. `/rth quiet 1` turns the dimming off entirely.

The seal icon, its countdown ring, and the last safe cast post are never dimmed
at all, since all three stay relevant in exactly the states the ring goes quiet
in.

## Colours

Not exposed through slash commands, deliberately. Edit the `ns.colors` table at
the top of `Config.lua`; values are `{r, g, b}` in the range 0 to 1.

If you change them, keep the brightness ordering intact: the window and pip
brightest, the seal colours mid, the blocked colour near black.

## How the swing timer works

TBC has no swing timer API, so it is reconstructed from the combat log. A swing
landing is also the instant the next swing begins, so every `SWING_DAMAGE` or
`SWING_MISSED` from you resynchronises the clock exactly. On top of that:

- Haste gained or lost mid swing scales the remaining time by the same ratio as
  the weapon speed rather than restarting the swing.
- Parrying an incoming attack pulls your next swing forward by 40% of your
  weapon speed, floored at 20% of it.
- If no swing event arrives within 0.55 s of the expected one you have stopped
  attacking, and the ring fades out.

The one unavoidable gap is the very first swing of a pull, which has no prior
event to sync against. It corrects itself on the first landed swing.

## Releasing

Tagging a version builds the zip and uploads it to CurseForge, via the
BigWigs packager in `.github/workflows/release.yml`.

```
git tag -a v1.0.1 -m "1.0.1"
git push origin v1.0.1
```

`## Version:` in the TOC is `@project-version@`, which the packager replaces
with the tag. That means a plain `git clone` shows the placeholder rather than a
number; only packaged builds carry a real version.

Two things have to be in place first, both one-time:

- A `CF_API_KEY` secret on the GitHub repo, from your CurseForge API tokens page
- The numeric project ID filled in after `## X-Curse-Project-ID:` in the TOC,
  from the CurseForge project page

If a release lands under the wrong game version on CurseForge, pin the flavour
by uncommenting the `args: -g bcc` block in the workflow rather than relying on
the `## Interface:` line to imply it.

## Files

| File | Contents |
| --- | --- |
| `Config.lua` | Defaults, saved variables, palette, slash commands |
| `Swing.lua` | Swing timer reconstruction |
| `Ring.lua` | The ring and the cooldown arcs, as coloured segment textures |
| `Options.lua` | The interface options panel |
| `MinimapButton.lua` | The minimap button |
| `Core.lua` | Seal and cooldown state, window logic, event wiring |
