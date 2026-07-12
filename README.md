# **MiraDropper**

**An UNOFFICIAL, easy to use Town of Us: Mira installer for Among Us.**

MiraDropper is a single double-click file that installs [Town of Us: Mira](https://github.com/AU-Avengers/TOU-Mira) on the **Steam** version of Among us. It finds your game, makes a mod copy, gets mod version from github, and then sets it up for you.

---

- [I swear no one reads to the bottom so CLICK HERE FOR TROUBLESHOOTING!!!!!!!](#troubleshooting)

---

## Requirements

- **Among Us on Steam** (this installer is Steam-only)
- A Windows PC (for now)
- ~1 GB of free disk space (it makes a separate modded copy of the game)

---

## Step 1 - Downgrade Among Us (do this)

The mod needs Among Us **v17.3**, not the latest version. **You have to switch this in Steam yourself.**
(as of 7-11-2026)

1. Open Steam and go to your **Library**
2. **Right-click** Among Us -> **Properties**
3. Click the **Beta** tab
4. In the dropdown, select **`public_previous`**
5. Wait for Steam to finish updating the game

Yay you did it.

---

## Step 2 Run the installer (Wow)

1. Download **`Install-TOU-Mira.bat`**
2. **Double-click it**
3. Answer the questions as they come up (see below)

You'll pick **Install** the first time. The installer will:

- Find your Among Us folder (or let you point it to the right one)
- Make a **separate modded copy**, your normal Among Us is never touched (other than downgrading it)
- Let you choose which mod version to install
- Download it, install it, and offer to make a Desktop shortcut

When it's done, launch the game from the **"Among Us (TOU Mira)"** Desktop shortcut (or the modded folder). If you see the Town of Us: Mira logo in the top-left corner, you're good.

---

## IMPORTANT for playing together

TOU:Mira is **client side**, so **everyone in the lobby must be on the same mod version**, or you will get kicked. /:

The installer will ask you for what version you want, so make sure you're friends have basic communication skills!

---

## Modes

| Mode            | What it does                               |
| --------------- | ------------------------------------------ |
| **[1] Install** | Installs the mod (wow who guessed)         |
| **[2] Update**  | Update the modded folder to a new version. |
| **[3] Remove**  | Deletes the modded copy and shortcut.      |

---

## Troubleshooting

**It couldn't find my Among Us folder.**
Choose the manual option when asked, then paste the folder path. To find it: in Steam, right click among us -> **Manage** -> **Browse Local Files**, and copy the path from the top of the window that opens.

**It says Among Us is running, but it's closed.**
Sometimes it lingers in the background for a few seconds. Wait a moment, or use the override option if you're sure it's closed.

**The game launches but there's no TOU Mira logo.**
Make sure you launched the **modded** copy (the Desktop shortcut or the `Among Us - TOU Mira` folder), not vanilla Among Us through Steam. Also double-check you did the Step 1 downgrade.

**Something else broke during install.**
There's a log file saved **next to the .bat** called `tou-mira-install-log.txt`. [Open an issue on the MiraDropper repo](https://github.com/Stanfoc/MiraDropper/issues/new) and paste the log in. MiraDropper is a custom installer, so its bugs don't get fixed by the official town of us team. (Please don't bug them)
 
**The mod itself is acting up** (game crashes, buggy roles, etc.) **once it's installed and running?**
Head to the [Town of Us Discord](https://discord.gg/ugyc4EVUYZ) support channel. (Don't send them the MiraDropper log, though! It's about the installer not the mod so it won't mean anything to them.)

---

*This installer isn't affiliated with Innersloth or the Town of Us team, I'm just automating their official Steam install steps.*
