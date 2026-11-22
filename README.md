# TSM Tooltip Control

A WoW Forever addon (Interface 16001) that lets you organize TradeSkillMaster's
tooltip datapoints under your own headings.

TSM groups its tooltip lines into fixed sections ("TSM General Info",
"TSM AuctionDB", ...). With this addon you can:

- create, rename, reorder and delete your own headings
- move any TSM datapoint (Min Buyout, Market Value, Vendor Sell Price, ...) under one of them, in any order
- move the "X auctions (Y ago)" text from the TSM AuctionDB heading onto its own
  line (the "Auctions" datapoint), under any heading
- show a single datapoint at heading level, as if it were its own heading
- add spacers (one blank line) between headings
- rename datapoints (e.g. "Min Buyout" → "Cheapest"); clear the name to go back to TSM's
- mute datapoints: draw them in gray as secondary information
- hide datapoints entirely
- choose whether unassigned datapoints stay under their original TSM heading or are hidden

Which datapoints appear at all is still controlled by TSM > Settings > Tooltip Settings.

## Install

The addon folder **must be named `!TSMTooltipControl`** (the `!` makes it load
before TradeSkillMaster, which the tooltip capture relies on):

```sh
# single quotes matter: zsh treats "!" inside double quotes as history expansion
ln -s /path/to/tsm-tooltip-control \
  '/Applications/World of Warcraft/_forever_/Interface/AddOns/!TSMTooltipControl'
```

## Use

- `/ttc` opens the options panel (also under Esc > Options > AddOns).
- `/ttc on` / `/ttc off` toggles the addon.
- Datapoints show up in the "Available datapoints" list after you've seen them
  on an item tooltip, so hover some items first.
- Requires TSM's "Embed TSM tooltip" option (the default). TSM's separate
  tooltip window isn't supported yet.

## Releasing

CurseForge builds and publishes the addon from this repo whenever a tag is
pushed (see `.pkgmeta`). Nothing needs uploading by hand.

1. Write the release notes in `CHANGELOG.md`. Its whole contents become the
   changelog for the new file on CurseForge, so it holds only the release being
   published.
2. Commit, then tag the commit with the version and push both:
   ```sh
   git tag 0.2.0
   git push && git push origin 0.2.0
   ```
   A tag containing `beta` or `alpha` (e.g. `0.2.0-beta1`) is published as a
   beta or alpha file instead of a release.

The tag name becomes the version shown in game (`## Version: @project-version@`
in the .toc). When the repo is symlinked for development, the version reads
`@project-version@` literally; that's expected.

The project description on CurseForge isn't part of packaging. `CURSEFORGE.md`
holds its text to paste in when it changes.

## How it works

TSM writes its lines from a `TooltipDataProcessor` post-call. This addon
registers one post-call before TSM's (at load) and one after (a frame after
`PLAYER_LOGIN`). In between, `AddLine`/`AddDoubleLine` on the tooltip are
temporarily redirected into a buffer; the buffered TSM block is parsed into
sections/datapoints, rebuilt using your headings, then written to the tooltip.
See `Capture.lua` and `Layout.lua`.

Datapoints are identified as `<TSM section> > <label>` (e.g.
`TSM AuctionDB > Min Buyout`), so they're tied to the client language and to
TSM's label text.
