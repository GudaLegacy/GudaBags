# GudaBags

A comprehensive **bag and bank management addon** for **World of Warcraft 3.3.5a (WotLK)**, targeted at the **Ascension Epoch** private server.

GudaBags provides a modern, unified bag/bank experience with multi-character support, sorting, item tracking, and quality-of-life tools. It is a port of the original Guda addon (built for Turtle WoW 1.12.1) adapted for 3.3.5a's client.

---

## 📦 Installation

1. Close the WoW client.
2. Copy the `GudaBags` folder into `Interface/AddOns/` of your Ascension Epoch install (e.g. `...\Ascension\resources\epoch-live\Interface\AddOns\GudaBags\`).
3. Launch the client and enable **GudaBags** in the AddOns list at the character-select screen.
4. Log in and type `/guda` — you should see `Loaded v…` in chat.

The TOC declares `## Interface: 30300` and is intended to run on 3.3.5a only. The 1.12 original lives in a separate `Guda` addon and is unaffected.

---

## 📦 Features

### 🎒 Bag Management

- **Unified Bag View** – All bags displayed in one window
- **Category View** – Group items by category for easier organization
- **Smart Sorting** – Sort by quality, name, or item type
- **Search Box** – Quickly find items (name, `~equipment`/`~consumable`/... category shortcuts, or `~t:<text>` tooltip search)
- **Quality Borders** – Items are visually color-coded based on rarity

### 🏦 Bank Management

- **Remote Bank Viewing** – View cached bank contents from anywhere
- **One-Click Sorting** – Organize your bank easily
- **Category View** – Group bank items by category
- **Persistent Storage** – Bank data saved between sessions

### 📊 Tracked Item Bar

- **Item Tracking** – Alt + Left-Click on any bag item to track it
- **Stack Display** – Shows tracked items as a single stack with total count
- **Farm Counter** – Displays how many items you currently have in your bags
- **Grinding Helper** – Perfect for tracking materials while farming
- **Draggable** – Shift + Left-Click to drag the bar anywhere on screen

### 📜 Quest Item Bar

- **Quest Item Display** – Shows usable quest items in up to 2 dedicated bars
- **Quick Swap** – Hover over a quest item bar slot to see available quest items
- **One-Click Replace** – Click on a popup item to swap it into the bar slot
- **Keybindable** – Set custom keybindings for quick quest item use
- **Draggable** – Shift + Left-Click to drag the bar anywhere on screen

### 👥 Multi-Character Support

- **Cross-Character Viewing** – View bags & banks of any character
- **Money Tracking** – See total gold across all characters, grouped by account and realm
- **Character Selector** – Switch characters quickly
- **Faction Filtering** – Shows only characters from the same faction
- **Global Item Counting** – Item totals across all characters, including:
    - Bags
    - Banks
    - Equipped items
    - Tooltip breakdown per character
- **Character Management** – Right-click the money frame to show/hide characters or remove deleted ones

### 💰 Money Display

- **Current Character Money**
- **Total Money Across All Characters**
- **Per-Character Overview** in the selector

---

## 📝 Slash Commands

| Command | Description |
|---------|-------------|
| `/guda` | Toggle bags |
| `/guda bank` | Toggle bank view |
| `/guda mail` | Toggle mailbox view |
| `/guda sort` | Sort your bags |
| `/guda sortbank` | Sort your bank (must be at a bank) |
| `/guda settings` | Open the settings window |
| `/guda openclams` | Open all clams in your bags |
| `/guda quest` | Toggle the quest-item bar |
| `/guda track` | Toggle the tracked-item bar |
| `/guda cleanup` | Remove characters not seen in 90 days |
| `/guda perf` | Show cache / button-pool performance stats |
| `/guda debug` | Toggle debug logging in chat |
| `/guda diag` | Print a runtime diagnostic (container state, pool stats, scanner health) |
| `/guda help` | Show help |
| `/gudatheme` | Switch between Guda / Blizzard themes |

---

## 🚀 How to Use

### Basic Usage

1. Press **B** or type `/guda` to open your bags.
2. Click **Characters** (top-left icon) to switch characters.
3. Click **Bank** to view your cached bank.
4. Click **Sort** to organize your bags.

### Sorting

- **Sort Bags**: Press **Sort** or use `/guda sort`
- **Sort Bank**: Use **Sort Bank** or `/guda sortbank`
- Sorting modes:
    - **Quality** (Epic → Rare → Uncommon → Common)
    - **Name** (A → Z)
    - **Type** (Item class & subclass)

### Category View

- Toggle category view in bags or bank to group items by type
- Easily find items organized by their category

### Tracked Item Bar

1. Open your bags
2. Hold **Alt** and **Left-Click** on any item to start tracking it
3. The item appears in the Tracked Item Bar with total count
4. Use **Shift + Left-Click** on the bar to drag it to your preferred location

### Quest Item Bar

1. Quest items automatically appear in the Quest Item Bar
2. Set keybindings via **Esc → Key Bindings → Guda** for quick use
3. Hover over a bar slot to see other available quest items
4. Click a popup item to swap it into that slot
5. Use **Shift + Left-Click** on the bar to drag it to your preferred location

---

## 🧠 Internal Systems

### 🔍 Bag Scanner

- Scans all bags at login
- Updates when looting, moving, or modifying items
- Stores item details (count, quality, name, link, etc.)

### 🏦 Bank Scanner

- Scans on bank open
- Saves snapshot for offline viewing
- Updates live while the bank is open

### 💰 Money Tracker

- Tracks money changes in real time
- Displays per-character, current character, and total money

### 🗄️ Data Storage

| Variable | Description |
|----------|-------------|
| `Guda_DB` | Global data: bag & bank contents, character money, timestamps, tracked items |
| `Guda_CharDB` | Per-character UI settings: bar positions, tracked item selections |

---

## ⚠️ Known Limitations

| Area | Limitation |
|------|------------|
| Sorting | Advanced sorting respects bag restrictions (soul bags, profession bags). Locked and soulbound items need special handling. |
| Bank Access | Must open the bank at least once to cache contents. |
| Faction Restriction | Only shows characters from the same faction. |
| Cross-Account Sharing | The optional GudaIO DLL is Turtle-WoW-specific and has no 3.3.5a equivalent; account data stays single-account on Ascension. |

---

## 🐞 Common Issues

### Cannot open bags using B

Set the keybinding: **Esc → Key Bindings → Guda → Toggle Bags**

### Silent issues / blank UI

Force Lua errors to surface and run the diagnostic:

```
/console scriptErrors 1
/guda debug
/guda diag
```

`/guda diag` prints the state of the bag frame, item container, button pool, and scanner to chat. If item slots are empty, watch for `BagFrame:Update() ERRORED:` lines — they pinpoint the failing call.

### Issues after updating the addon

Delete outdated saved variables:

```
WTF/Account/<ACCOUNT_NAME>/SavedVariables/Guda_DB.lua
WTF/Account/<ACCOUNT_NAME>/SavedVariables/Guda_DB.lua.bak
WTF/Account/<ACCOUNT_NAME>/<REALM>/<CHARACTER>/SavedVariables/Guda_CharDB.lua
```

---

## 🔧 3.3.5a Port Notes

This build contains compatibility fixes versus the Turtle-WoW 1.12 original, driven by Ascension Epoch's modernized Blizzard UI:

- **ItemButton template** passes `this` explicitly to `ContainerFrameItemButton_OnLoad` / `ContainerFrameItemButton_OnClick` (Ascension uses `self`-parameter signatures, not the vanilla implicit `this`).
- **UIDropDownMenu** calls use the modern `(frame, …)` argument order for `SetWidth` and `SetText`.
- **FauxScrollFrame_OnVerticalScroll** calls pass `(this, arg1, itemHeight, updateFn)`.
- **Varargs** (`Utils:SafeCall`) use native Lua 5.1 `...` forwarding instead of the legacy `arg` table, which isn't reliably populated on Ascension.
- **Bag hooks** (`ToggleBackpack`, `OpenAllBags`, `CloseAllBags`, `OpenBag`, `ToggleBag`, plus `OpenBackpack`/`CloseBackpack`/`CloseBag`) are installed synchronously in `BagFrame:Initialize` instead of via a deferred `PLAYER_LOGIN` frame that never fired post-login.
- **Event handler** guards invalid bag IDs before calling `ContainerIDToInventoryID`, which raises a hard error on out-of-range IDs rather than returning nil.
- **ITEM_LOCK_CHANGED** in single view now triggers a lightweight `UpdateLockStates` directly instead of a throttled redraw that could be cancelled by a follow-up `BAG_UPDATE`, preventing the "stuck desaturated" look after successful swaps.
- All asset paths were rewritten from `Interface\AddOns\Guda\...` to `Interface\AddOns\GudaBags\...`.

---

## 📢 Support

For bugs or feature requests, please open an issue. Your feedback helps improve the addon.
