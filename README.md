# WhatToDo

**[Українська](#українська) | [English](#english)**

---

## Українська

Аддон для **WoW Forever**, який підказує, чим зараз найвигідніше зайнятися, і сортує варіанти за золотом за годину:

- **рекрафт** — купити дешеві матеріали на аукціоні, скрафтити, продати;
- **фарм мобів і збір** — майнінг, трави, скінінг, риболовля (за вашою історією з Yield).

Кожна порада має **рівень довіри**: свіжість цін аукціону (до 6 год — повна, понад 12 год — ненадійна) і, головне, ваш **фактичний результат** — реальні продажі з пошти. Аддон сам веде журнал продажів, повернень, купівель і часу на крафт і коригує за ним прогнози.

### Залежності

| Аддон | Навіщо | Обов'язковий |
|---|---|---|
| [Auctionator](https://www.curseforge.com/wow/addons/auctionator) | ціни аукціону | ні, але без нього рекрафт не працює |
| [Yield](https://www.curseforge.com/wow/addons/yield) | сесії фарму | ні, але без нього немає порад по фарму |

### Встановлення з автооновленням (Windows)

Відкрийте **PowerShell** (Пуск → введіть `PowerShell`) і вставте:

```powershell
irm https://raw.githubusercontent.com/Diogen8/WhatToDo/main/install/install.ps1 | iex
```

Скрипт:
1. встановить Git, якщо його немає;
2. знайде папку WoW Forever (або спитає, де вона);
3. поставить аддон у `Interface\AddOns\WhatToDo`;
4. додасть у Планувальник завдань оновлення при вході в Windows і щогодини.

Нова версія підхопиться після `/reload` або перезаходу в гру. Аддон також повідомить у чаті, якщо в когось з гільдії, групи чи друзів новіша версія.

Щоб прибрати автооновлення: Планувальник завдань → `WhatToDo update` → Видалити.

### Встановлення вручну

[Завантажте архів](https://github.com/Diogen8/WhatToDo/archive/refs/heads/main.zip), розпакуйте і перейменуйте папку `WhatToDo-main` на `WhatToDo` у `World of Warcraft\_forever_\Interface\AddOns`.

### Користування

`/wtd` або кнопка-монета біля мінікарти. При першому вході відкривається інструкція, пізніше — `/wtd guide` або кнопка «?». Мова перемикається кнопкою EN/UA або `/wtd lang en|uk`.

---

## English

An addon for **WoW Forever** that suggests what is most profitable to do right now and ranks the options by gold per hour:

- **recraft** — buy cheap materials on the auction house, craft, sell;
- **mob farming and gathering** — mining, herbalism, skinning, fishing (from your Yield history).

Every suggestion has a **trust level**: how fresh the auction prices are (up to 6 h — full, over 12 h — unreliable) and, above all, your **actual results** — real sales from the mail. The addon keeps its own ledger of sales, returns, purchases and craft times and corrects its forecasts by it.

### Dependencies

| Addon | Why | Required |
|---|---|---|
| [Auctionator](https://www.curseforge.com/wow/addons/auctionator) | auction prices | no, but recraft needs it |
| [Yield](https://www.curseforge.com/wow/addons/yield) | farming sessions | no, but farming suggestions need it |

### Install with auto-update (Windows)

Open **PowerShell** (Start → type `PowerShell`) and paste:

```powershell
irm https://raw.githubusercontent.com/Diogen8/WhatToDo/main/install/install.ps1 | iex
```

The script:
1. installs Git if it's missing;
2. finds your WoW Forever folder (or asks where it is);
3. puts the addon into `Interface\AddOns\WhatToDo`;
4. adds an update to Task Scheduler at Windows logon and every hour.

A new version is picked up after `/reload` or relogging. The addon also tells you in chat when someone in your guild, group or friends list has a newer version.

To remove the auto-update: Task Scheduler → `WhatToDo update` → Delete.

### Manual install

[Download the archive](https://github.com/Diogen8/WhatToDo/archive/refs/heads/main.zip), unzip it and rename the `WhatToDo-main` folder to `WhatToDo` inside `World of Warcraft\_forever_\Interface\AddOns`.

### Usage

`/wtd` or the coin button at the minimap. A guide opens on first login; later use `/wtd guide` or the "?" button. Switch the language with the EN/UA button or `/wtd lang en|uk`.

---

License: MIT
