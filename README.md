# WhatToDo 0.21.1

**[Українська](#українська) | [English](#english) | [For AI agents](#for-ai-agents-install-and-update)**

**Latest version: see [`release/VERSION`](release/VERSION) — download: [WhatToDo.zip](https://github.com/Diogen8/WhatToDo/raw/main/release/WhatToDo.zip)**

---

## Українська

Аддон для **WoW Forever**, який підказує, чим зараз найвигідніше зайнятися, і сортує варіанти за золотом за годину:

- **рекрафт** — купити дешеві матеріали на аукціоні, скрафтити, продати;
- **фарм мобів і збір** — майнінг, трави, скінінг, риболовля (за вашою історією з Yield).

Кожна порада має **рівень довіри**: свіжість цін аукціону і, головне, ваш **фактичний результат** — реальні продажі з пошти. Аддон сам веде журнал продажів, повернень, купівель і часу на крафт і коригує за ним прогнози.

### Залежності

| Аддон | Навіщо | Обов'язковий |
|---|---|---|
| [Auctionator](https://www.curseforge.com/wow/addons/auctionator) | ціни аукціону | ні, але без нього рекрафт не працює |
| [Yield](https://www.curseforge.com/wow/addons/yield) | сесії фарму | ні, але без нього немає порад по фарму |

> **Важливо про Yield:** за замовчуванням він записує фарм лише поки його вікно відкрите. Після встановлення увімкніть у Yield: **Settings → Tracking → Record when Yield is closed** (або наберіть у грі `/wtd yield` — WhatToDo увімкне сам). WhatToDo нагадає при вході в гру, якщо галка вимкнена.

### Встановлення та оновлення

Найпростіше — попросіть свого ШІ-агента: *«Встанови (або онови) аддон WhatToDo для WoW Forever за інструкцією з https://github.com/Diogen8/WhatToDo»*. Розділ [For AI agents](#for-ai-agents-install-and-update) нижче написаний саме для нього.

Вручну:
1. Завантажте [WhatToDo.zip](https://github.com/Diogen8/WhatToDo/raw/main/release/WhatToDo.zip).
2. Видаліть стару папку `World of Warcraft\_forever_\Interface\AddOns\WhatToDo`, якщо вона є.
3. Розпакуйте архів у `World of Warcraft\_forever_\Interface\AddOns` — має вийти `AddOns\WhatToDo\WhatToDo.toc`.
4. Перезапустіть гру.

Оновлення — те саме: завантажити свіжий архів і замінити папку. Ваші дані (`WTF`) не зачіпаються. Аддон сам повідомить у чаті, якщо в когось з гільдії, групи чи друзів новіша версія.

### Користування

`/wtd` або кнопка-монета біля мінікарти. При першому вході відкривається інструкція, пізніше — `/wtd guide` або кнопка «?». Мова: кнопка EN/UA або `/wtd lang en|uk`.

---

## English

An addon for **WoW Forever** that suggests what is most profitable to do right now and ranks the options by gold per hour:

- **recraft** — buy cheap materials on the auction house, craft, sell;
- **mob farming and gathering** — mining, herbalism, skinning, fishing (from your Yield history).

Every suggestion has a **trust level**: how fresh the auction prices are and, above all, your **actual results** — real sales from the mail. The addon keeps its own ledger of sales, returns, purchases and craft times and corrects its forecasts by it.

### Dependencies

| Addon | Why | Required |
|---|---|---|
| [Auctionator](https://www.curseforge.com/wow/addons/auctionator) | auction prices | no, but recraft needs it |
| [Yield](https://www.curseforge.com/wow/addons/yield) | farming sessions | no, but farming suggestions need it |

> **Important about Yield:** by default it records farming only while its window is open. After installing, turn on in Yield: **Settings → Tracking → Record when Yield is closed** (or type `/wtd yield` in game and WhatToDo turns it on). WhatToDo reminds you at login while it's off.

### Install and update

Easiest: ask your AI agent *"Install (or update) the WhatToDo addon for WoW Forever following https://github.com/Diogen8/WhatToDo"*. The [For AI agents](#for-ai-agents-install-and-update) section below is written for it.

By hand:
1. Download [WhatToDo.zip](https://github.com/Diogen8/WhatToDo/raw/main/release/WhatToDo.zip).
2. Delete the old `World of Warcraft\_forever_\Interface\AddOns\WhatToDo` folder if there is one.
3. Unzip into `World of Warcraft\_forever_\Interface\AddOns` — you should get `AddOns\WhatToDo\WhatToDo.toc`.
4. Restart the game.

Updating is the same: download the fresh zip and replace the folder. Your data (`WTF`) is not touched. The addon tells you in chat when someone in your guild, group or friends list has a newer version.

### Usage

`/wtd` or the coin button at the minimap. A guide opens on first login; later use `/wtd guide` or the "?" button. Language: the EN/UA button or `/wtd lang en|uk`.

---

## For AI agents: install and update

Follow these steps exactly. The same procedure installs and updates. Ask the user before anything not listed here.

**Sources**
- Latest zip: `https://github.com/Diogen8/WhatToDo/raw/main/release/WhatToDo.zip`
- Latest version (plain text, one line): `https://raw.githubusercontent.com/Diogen8/WhatToDo/main/release/VERSION`
- The zip contains exactly one top-level folder, `WhatToDo/`, with `WhatToDo.toc` and the `.lua` files.

**1. Find the game folder.** The target is the WoW Forever client folder, named `_forever_`, inside the World of Warcraft install (it contains `Wow.exe`, `Interface`, `WTF`). Common places: `C:\Program Files (x86)\World of Warcraft\_forever_`, `<drive>:\World of Warcraft\_forever_`, `<drive>:\Games\World of Warcraft\_forever_`. On Windows the Battle.net install path is also in the registry at `HKLM\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft` (`InstallPath`). If you can't find it, ask the user. Do not use `_retail_`, `_classic_` or `_classic_era_` folders.

**2. Check what is installed.** The addon folder is `<_forever_>\Interface\AddOns\WhatToDo`. If `WhatToDo.toc` exists there, its line `## Version: X.Y.Z` is the installed version. Fetch the latest version from the `VERSION` URL. If they are equal, tell the user it is up to date and stop. Compare versions numerically part by part (`0.10.0` is newer than `0.9.9`).

**3. If the installed folder is a git repository** (`<AddOns>\WhatToDo\.git` exists), it belongs to the developer: do not replace it, tell the user and stop.

**4. Download** the zip to a temporary location and check it is a valid zip containing `WhatToDo/WhatToDo.toc`.

**5. Install.**
- Create `<_forever_>\Interface\AddOns` if it doesn't exist.
- Delete the old `<AddOns>\WhatToDo` folder completely (old files must not stay behind), then extract the zip into `<AddOns>`.
- Result: `<_forever_>\Interface\AddOns\WhatToDo\WhatToDo.toc`. Not `AddOns\WhatToDo\WhatToDo\...` and not `AddOns\WhatToDo-main\...`.
- **Never touch** `<_forever_>\WTF` (saved data and settings) or any other addon folder.
- Delete the temporary zip.

**6. Verify** that `WhatToDo.toc` is in place and its version equals the `VERSION` file.

**7. Tell the user:**
- which version was installed (and which it replaced);
- to fully restart the game if it is running (a new or updated addon is loaded at game start; `/reload` is enough only when no files were added or removed, so restarting is the safe advice);
- in game: `/wtd` opens the window, `/wtd guide` the guide;
- that the optional dependencies **Auctionator** and **Yield** come from CurseForge, if they are not in `<AddOns>` yet (folders `Auctionator`, `Yield`).
- if Yield is used: by default it records only while its window is open, so in Yield turn on **Settings → Tracking → Record when Yield is closed**, or type `/wtd yield` in game.

---

License: MIT

NPC levels in `MobLevels.lua` are facts extracted from the [Questie](https://github.com/Questie/Questie) project's database (QuestieDB, WoW Forever data) with `tools/extract_mob_levels.py`. Thanks to the Questie team and its data contributors.
