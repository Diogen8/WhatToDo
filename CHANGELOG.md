# Changelog

## 0.17.3
- A click on a farming or gathering row opens the world map on its zone and pins the spot (WhatToDo notes where you loot; spots farmed before this version get a point after the next loot there).
- Mob farming has a paw icon; the tab icons are smaller.

## 0.17.2
- The "All" tab is one list, best first, instead of a section per activity; every row has its activity's icon (the same icons are on the tabs and in the tooltip).

## 0.17.1
- "Recraft if learned" no longer suggests a profession that one of your characters already has.

## 0.17.0
- Trust model, stage 2 (model 1). Rows show a range (8 cases in 10) and the chance of success instead of one number and "trust":
  - recraft: item groups with their own starting assumptions (gear: little sells and the price swings; consumables steady; materials steadiest), refined by real sales (friends' at half weight) and closed batches; the batch is capped at what the market takes in 2 days; 300 scenarios per suggestion (units sold, price, unsold at vendor price, active time); success = in profit. Suggestions whose optimistic case still loses are hidden (`/wtd check` says why).
  - farming: next session = the spot's rate times a spread learned from checked sessions, time behind the spot, price age and gear share; success = at least half the forecast.
  - tooltips: median, batch profit range, when the money is back, what makes it uncertain.

## 0.16.1
- Mob levels are built in (MobLevels.lua, ~9900 hostile and neutral NPCs extracted from QuestieDB's Forever data), so Questie is no longer needed. Levels seen in game still widen and complete them.

## 0.16.0
- Mob farming spots are left out when their mobs are more than 2 levels above the current character (levels from Questie, else seen on targets / mouseover / nameplates).
- "If learned" respects the character level a trainer requires: rank 75+ from level 10, 150+ from 20, 225+ from 35.

## 0.15.0
- Trust model, stage 1: collecting outcomes. Recraft batches (cost from purchase lots first-in-first-out, active time with the AH, mail and profession windows, posts, sales, returns; closed when all sold or 2 days after posting, unsold at vendor price; success = profit). Farm sessions checked against earlier sessions at the same spot (success = at least half the forecast), including sessions recorded before. `/wtd results`, batch line in recraft tooltips.

## 0.14.0
- Sharing checks the data format, not the addon version: copies with different versions can share as long as the format of the shared data is the same. The format (shown by `/wtd version`) changes only when the shared data's structure or meaning changes. Sharing with 0.12-0.13 is not possible (they demand an identical version).

## 0.13.2
- Fix: "WhatToDo has been blocked from an action only available to the Blizzard UI". The StaticPopupDialogs global was reassigned, which tainted every Blizzard popup.

## 0.13.1
- Repository: `release/WhatToDo.zip` and `release/VERSION`, README with install/update steps for AI agents.
- "?" next to the share button: tooltip and a sharing guide page.

## 0.13.0
- Guide window (dependencies with live status, features, first steps, commands), shown once on first login. UA/EN.

## 0.12.0
- Share data with a targeted group member on request: same version, nearby, the receiver must accept. Received data is kept apart: friends' sales weigh half, a friend's price is used only when fresher, friends' farm spots are added.

## 0.11.0
- Ukrainian / English switch (EN/UA button, `/wtd lang`).

## 0.10.0
- Version check between players (guild, group, online friends) with an update notice.

## 0.9.0
- Trust = 40% price freshness + 60% evidence of real gold. Never done: 40% at most.

## 0.8.0
- Trust level from price freshness: exact scan times via Auctionator; up to 6 h full, 6-12 h falling, over 12 h unreliable.

## 0.7.0
- WoW Forever support: skills via C_SkillInfo, recipes via C_TradeSkillUI. `/wtd check`, `/wtd debug`.
- Click a recraft row to open its recipe in the profession window.

## 0.6.0
- Minimap button.

## 0.5.0
- Gathering split into Mining, Herbalism, Skinning and Fishing tabs.

## 0.4.0
- Account-wide ledger of real AH sales, returns, purchases and craft times; forecasts corrected by it.

## 0.3.0
- Recraft across all characters by their professions and ranks; built-in catalog of trainer recrafts; "if learned" section.

## 0.2.0
- Separate recraft and farm sections.

## 0.1.0
- First version: farm spots from Yield and AH recrafts from Auctionator ranked by gold per hour.
