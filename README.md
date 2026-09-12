# Page Turn Animation for KOReader

KOReader page-turn animation plugin for Kindle Paperwhite 4 / Rex, extracted from `koplugin-experiments`.

The installable plugin folder is `page-turn-animation.koplugin`. The internal plugin ID and settings keys remain `animationlab` so existing KOReader settings continue to work.

Version 0.7.0 keeps the fast six-step KPW4 reveal and adds page-like reveal geometry without bringing back the slow curl renderer.

## How it works

For a normal one-page turn:

1. KOReader handles navigation and renders the destination page normally.
2. The plugin snapshots the old framebuffer before paint and captures the completed destination framebuffer immediately before the first physical refresh.
3. The destination is revealed in **6 temporal steps**.
4. Each step submits only **one E-Ink update**. Straight mode uses the original full-height strip. Shaped modes calculate the edge in 24 horizontal bands in RAM, then refresh one bounding rectangle around all newly revealed pixels.
5. After the animation the exact destination framebuffer is restored.
6. Normally one full-screen `refreshUI()` / AUTO settle is performed. Optionally, **Full clean refresh afterwards** replaces that settle with `refreshFull()` for stronger ghost cleanup.

## Reveal shapes

- **Straight vertical (ZIP original)**
- **Diagonal — bottom first**
- **Curved bottom flip**

## Page-turn animation settings

- **Waveform:** AUTO / UI, DU / Fast, or A2
- **Scheduling:** free-running or fixed interval
- **Strip delay:** 0, 5, 10, 20, 30, 40, 50, 60, 80, or 100 ms
- **Full clean refresh afterwards:** optional `refreshFull()` cleanup

## Known-good baseline

- Straight vertical
- AUTO / UI
- Free-running
- 40 ms
- Full clean refresh afterwards: off
- 6 temporal steps

## Installation

Copy `page-turn-animation.koplugin` into KOReader's `plugins` directory and restart KOReader.

## Self-update

The final menu entry, **update plugin**, updates `page-turn-animation.koplugin` from this repository's `main` branch, verifies revision/blob integrity, syntax-checks downloaded Lua, stages the replacement, retains a rollback backup, and offers to restart KOReader.
