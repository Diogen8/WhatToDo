# Changelog

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
