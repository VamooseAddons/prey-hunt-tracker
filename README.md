# Prey Hunt Tracker

See at a glance which prey target finishes an achievement before you pick.

A small World of Warcraft: Midnight addon that annotates Astalor Bloodsworn's
"Prey: Preferential Killing" gossip menu with priority icons, plus a tabbed
panel that mirrors your full Prey-category achievement state.

## Install

- **CurseForge:** https://www.curseforge.com/wow/addons/prey-hunt-tracker
- **Manual:** download a zip from
  [Releases](../../releases), extract into
  `World of Warcraft/_retail_/Interface/AddOns/`.

## What it does

When you talk to Astalor in Silvermoon, every prey-target option in the
gossip menu carries a priority icon based on your character's achievement
progress:

- Gold star: hunting this prey will FINISH an achievement
- Yellow dot: hunting this prey progresses an unfinished achievement
- Green check: every achievement that uses this prey is already earned
- No icon: not part of any indexed Prey-category achievement

Hover any decorated row for a tooltip showing exactly which achievements
feed that target, split into "Will progress" vs "Already credited".

The follow-up "How viciously?" difficulty selector is annotated the same
way -- icon and tooltip reflect whether the chosen target on
Normal / Hard / Nightmare would finish or progress a Prey: achievement.

Random Hunt mode is supported: each difficulty is classified by overall
progress at that tier. When a Random Hunt rolls, a chat line announces
the assigned target with the same classification so you can see at a
glance whether the rolled prey is worth chasing.

Works with both the default Blizzard gossip frame and DialogueUI.

## Panel (`/pht`)

Tabbed window:

- **Status** -- live dashboard: hunt heat, hunts available, distance,
  Preyseeker renown, Anguish currency, achievement totals, finisher
  count, active prey quest, torment debuff.
- **Targets** -- every Prey achievement broken down two ways:
  - *By Achievement*: collapsible per-achievement view with criteria
    pills and decor-reward callouts. Objective achievements (Cook 100
    things, Catch 100 fish) show their inline counter.
  - *By Target*: per-NPC view, sorted by how many open achievements
    still need their kill.

## Slash commands

- `/pht` -- toggle the panel
- `/pht scan` -- force a rescan of the prey hunt widget
- `/pht overlay` -- toggle the dot-strip overlay
- `/pht state` -- dump live widget data (debug aid)

## Compatibility

Coexists with DialogueUI, Plumber, Preydator, and similar gossip /
progress-bar enhancers. PHT focuses on achievement decision support;
the others handle visual polish around the same Blizzard widget.

## Support

- Discord: https://discord.gg/RWZaxJaHFP
- Issues: https://github.com/VamooseAddons/prey-hunt-tracker/issues

## License

MIT. See [LICENSE](LICENSE).
