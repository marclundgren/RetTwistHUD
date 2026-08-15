# Changelog

## 1.2.0

- The twist window now draws thicker than the rest of the ring. It was already
  white at full alpha, so there was no brighter available and the extra
  salience had to come from size, which peripheral vision reads better than
  colour anyway. `/rth boost` tunes it. Only the pressable part swells, so a
  window the global cooldown has eaten stays thin.
- A pulse now fires after a swing you twisted in time for. It plays once the
  swing has landed, so it costs no attention during the window. What it detects
  is that the finisher seal went up inside the window before the swing
  resolved, which is your timing being right; no combat log event reports that
  a twist paid out, and it claims nothing more than it can see.

## 1.1.1

- The last safe cast post is now drawn on every live swing rather than only
  while a twist seal is up. The deadline belongs to the swing and the global
  cooldown, not to the seal, so it was the same instant all along and only the
  gate was wrong.
- The post is no longer dimmed by the quiet setting, joining the seal readout
  on the always-bright layer. It stays relevant in exactly the states the ring
  goes quiet in.

## 1.1.0

- The last safe cast post now shows while either twist seal is up, not only
  Seal of Command. With Seal of Blood up it tells you whether you can still
  swap back to Seal of Command in time for this swing's twist, which is the
  same instant and the same arithmetic, but a far more expensive deadline to
  miss.
- The ring no longer dims while you hold either twist seal. Dimming keyed on
  the twist window being armed, which meant the post went quiet in exactly the
  state where it was the only thing worth looking at.

- Show an icon for whichever seal you have up, with a thin ring around it
  counting down the seal's remaining duration. `/rth sealangle` puts it
  anywhere around the ring; it sits above your head by default.
- Track every paladin seal rather than only the two you twist between. Seal of
  the Crusader now shows its own icon, and it counts as a seal for the
  seal-aware visibility modes. Previously `/rth show seal` and `/rth show both`
  would hide the ring entirely while Seal of the Crusader was up.
- The seal readout is exempt from the quiet dim. Which seal is up is exactly
  what you want to know when nothing else is happening, and it was previously
  dimmest whenever no twist was pending.

## 1.0.0

First release.

A swing timer for TBC retribution paladins that lives around your character
instead of at the bottom of the screen, so seal twisting can be timed without
looking away from the middle of the screen.

- Swing ring centred on your character, with nothing drawn inside it
- Twist window shown as the brightest thing on the ring, shifted back by your
  latency so the press leaves the client in time
- Active seal shown as the ring colour, and the window only drawn when a twist
  is actually available
- Current global cooldown painted on the ring, and it trims the window so the
  lit part never covers time you cannot press in
- A post marking the last moment you can start a global cooldown spell and
  still make the twist
- Judgement and Crusader Strike cooldown arcs, with four layouts for where
  Crusader Strike sits
- Contrast from a dark groove under every element, so the ring stays readable
  over fire, grass or a lit floor
- Options window, minimap button, and a slash command for every setting
