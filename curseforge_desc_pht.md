# Prey Hunt Tracker

**Stop guessing which prey to hunt. See at a glance which target finishes
an achievement, which one's already credited, and which one is just chrome
for your week.**

Prey Hunt Tracker plugs into Astalor Bloodsworn's "Prey: Preferential
Killing" menu and annotates every option with a priority icon, then gives
you a tabbed panel that mirrors your full Prey-category achievement state
without alt-tabbing through the achievement frame.

---

## Astalor's menu, annotated

When you talk to Astalor in Silvermoon, every prey-target option carries
a priority icon based on your character's achievement progress:

- **Gold star** -- hunting this prey will FINISH an achievement
- **Yellow dot** -- hunting this prey progresses an unfinished achievement
- **Green check** -- every achievement that uses this prey is already earned
- **No icon** -- not part of any indexed Prey-category achievement

Hover any row for a tooltip that splits the feeding achievements into
*Will progress* vs *Already credited* so you can tell at a glance which
prey is still worth your week.

The "How viciously?" difficulty step is annotated too -- icon and tooltip
reflect whether the chosen target on Normal/Hard/Nightmare would finish
or progress a Prey: achievement. **Random Hunt mode** is supported: each
difficulty is classified by overall progress at that tier.

When a Random Hunt rolls a target, a chat line announces it:

```
[Prey Hunt Tracker] [*] Hunt assigned: Consul Nebulor (Nightmare) -- will FINISH an achievement!
```

Works with both the default Blizzard gossip frame and **DialogueUI**.

---

## Tabbed Tracker Panel (/pht)

### Status tab -- live hunt dashboard

- Current hunt state (Cold / Warm / Hot or "Awaiting hunt start")
- Hunts available + distance to your active objective
- Preyseeker renown progress + Anguish currency
- Achievement totals: earned, points, targets left, and the count of
  "finisher" kills available right now
- Active prey quest with per-objective progress
- Torment difficulty (Hard / Nightmare), stack count, and remaining duration

### Targets tab -- the achievement planner

Two views, toggleable:

**By Achievement** (default) -- every Prey-category achievement, sorted by
unearned-first. Click any row to expand its criteria. Each entry shows:

- Per-criterion pills: ASCII glyph + NPC name + "this kill finishes it"
  highlight on the last unfinished criterion
- OR badge for achievements that take any one of multiple targets
- Decor reward callout (e.g. *Decor Reward: Preyseeker's Magister Bust*)
- Objective-style achievements (Cook 100 things, Catch 100 fish, etc.)
  show their live count inline (0 / 100)

**By Target** -- one row per named NPC, sorted by how many Prey:
achievements still need their kill. Hover for the list of feeding
achievements with completion glyphs.

---

## Other Features

- **Dot-strip overlay** beneath Blizzard's prey progress widget -- four
  dots scaling Hidden / Cold / Warm / Hot, current state highlighted and
  enlarged. Toggleable.
- **Auto-detection** -- finds the active prey hunt widget in any zone
  without configuration.
- **Lazy build** -- the achievement index builds on first need (panel
  open or Astalor interaction). Zero login-time cost.
- **Reactive** -- panel and gossip overlay update live on
  ACHIEVEMENT_EARNED, CRITERIA_UPDATE, and CRITERIA_COMPLETE.
- **Compatible** -- coexists with DialogueUI, Plumber, Preydator, and
  similar gossip / progress-bar enhancers. Both Preydator and PHT read the
  same Blizzard widget; PHT's focus is achievement decision support (which
  target, which difficulty), Preydator's is custom progress visuals.

---

## Slash Commands

- `/pht` -- toggle the panel
- `/pht scan` -- force a rescan of the prey hunt widget
- `/pht overlay` -- toggle the dot-strip overlay
- `/pht state` -- dump live widget data (debug aid)

---

## Requirements

- World of Warcraft: Midnight (TOC 120005)
- An active Prey: Season 1 character (Astalor's gossip needs to be
  unlocked for the overlay to do anything)

---

## Support & Feedback

Found a bug, want a feature, or hit a weird interaction with another
addon? Drop into the Discord -- I read everything in there.

Discord: https://discord.gg/RWZaxJaHFP

---

**Author:** Vamoose
**Version:** 1.0.1
**Game Version:** 12.0.5+ (Midnight)
