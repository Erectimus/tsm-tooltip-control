# TSM Tooltip Control

**Your tooltip, your order.**

**TradeSkillMaster puts a lot of useful numbers on your tooltips, but it decides how they're grouped. TSM Tooltip Control lets you make your own headings, put any TSM datapoint under them in any order, rename them and hide the rest.**

---

## Why it exists

TSM lets you choose which datapoints appear on your tooltips. It doesn't let you choose where they go. Min Buyout lives under "TSM AuctionDB", Vendor Sell Price lives under "TSM General Info", and Crafting Cost lives under "TSM Crafting". The numbers you compare most often end up spread across three headings.

TSM Tooltip Control lets you group them the way you think about them. Put Min Buyout, Market Value and Vendor Sell Price together under a heading called Prices. Put crafting and disenchant values under Profit. Give a datapoint a shorter name, hide the ones you never read, and add a blank line wherever the tooltip feels crowded.

TSM still decides what data you see. This addon only decides how it's laid out.

---

## Features

- **Your own headings.** Create as many as you like, name them anything and put them in any order.
- **Move any datapoint.** Put any TSM line under any of your headings, in the order you want.
- **Rename datapoints.** Turn "Region Sale Avg" into "Sells for", or anything else. Clear the name to go back to TSM's.
- **Mute secondary datapoints.** Show a datapoint in gray so the numbers you check most stand out, without hiding the rest.
- **Hide what you don't need.** Drop a datapoint into Hidden and it's gone from every tooltip.
- **Spacers.** Add a blank line between headings. Spacers that would sit at the top or bottom of the tooltip are skipped.
- **Promote a datapoint.** Show a single line at heading level, as if it were its own heading.
- **Auction count on its own line.** The "12 auctions (3 min ago)" text on the TSM AuctionDB heading can be moved, renamed or hidden like any other datapoint.
- **Keeps the details.** Disenchant and crafting material breakdowns stay attached to their datapoint, and the stack total you see while holding Shift still works.
- **Nothing gets lost.** Anything you haven't placed stays under its original TSM heading. Untick one box if you'd rather hide it.

---

## Example

```
Last scan               8 auctions (3 min ago)

Prices
  Min Buyout            12g
  Market Value          14g 50s
  Vendor Sell Price     1g 20s

Profit
  Disenchant Value      5g
    Strange Dust x2     1g
```

---

## Getting started

1. Hover over a few items so the addon can see which datapoints TSM shows you.
2. Type `/ttc`, or open Esc > Options > AddOns > TSM Tooltip Control.
3. Click **New Heading** to create a heading.
4. Drag datapoints from the right-hand list into it.
5. Hover an item again to see your new layout.

### In the options panel

**Your layout** on the left shows your headings in tooltip order, with each heading's datapoints listed under it.

- **Drag** a datapoint into a heading, or to a new spot in the same heading. Drag it into **(Hidden)** to never show it, or back to the right-hand list to take it out of your layout.
- **Drag a datapoint between two headings** to show it at heading level, as if it were its own heading.
- **Drag headings and spacers** to reorder them.
- **Double-click** a heading or datapoint to rename it.
- **Rename** changes a heading's or datapoint's label.
- **Spacer** adds a blank line below the selected heading.
- **Mute** shows a datapoint in gray. Click **Unmute** to bring back its normal colors.
- **Hide** moves a datapoint to (Hidden). **Unhide** puts it back.
- **Show at Heading Level** turns a single datapoint into its own heading-level line.

Type `/ttc off` and `/ttc on` to switch the addon off and on.

---

## Requirements

- **TradeSkillMaster.** This addon rearranges TSM's tooltip, so TSM has to be installed and showing tooltip data.
- **TSM's "Embed TSM tooltip" option**, which is on by default. TSM's separate tooltip window isn't supported yet.
- **English game client.** Datapoints are recognised by their names, so other languages may not work yet.

---

## Built to stay out of the way

TSM Tooltip Control doesn't change TSM or its settings. It doesn't calculate any prices of its own either. Every number you see comes straight from TSM. Turn the addon off and your tooltips go back to exactly what TSM shows.
