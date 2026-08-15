# Changelog

## 1.1.0

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
