# Page Turn Animation

KOReader page-turn animation plugin for E-Ink devices, currently tuned around the Kindle Paperwhite 4 / Rex display path.

Version **0.1.0** provides a fast six-step reveal with straight, diagonal, and curved-bottom edge shapes.

## How it works

For a normal one-page turn:

1. KOReader handles navigation and renders the destination page normally.
2. Page Turn Animation snapshots the old framebuffer before paint and captures the completed destination framebuffer immediately before the first physical refresh.
3. The destination is revealed in **6 temporal steps**.
4. Each step submits only **one E-Ink update**. Straight mode uses a full-height strip. Shaped modes calculate the edge in 24 horizontal bands in RAM, then refresh one bounding rectangle around all newly revealed pixels.
5. After the animation the exact destination framebuffer is restored.
6. Normally one full-screen `refreshUI()` / AUTO settle is performed. Optionally, **Full clean refresh afterwards** replaces that settle with `refreshFull()` for stronger ghost cleanup.

## Reveal shapes

### Straight vertical

One vertical reveal edge moves across the page.

### Diagonal — bottom first

The bottom edge leads while the top lags, producing a diagonal page-turn edge. The lead is strongest around the middle of the animation and disappears at the end so top and bottom finish aligned.

### Curved bottom flip

Lower parts of the page accelerate early with quadratic vertical weighting, creating a curved edge. The bottom then slows relative to the top so the edge straightens and the full page finishes aligned.

The shaped modes still issue only six physical panel updates total; the extra geometry is calculated in the framebuffer before each update.

## Page-turn animation settings

### Reveal shape

- **Straight vertical (default)**
- **Diagonal — bottom first**
- **Curved bottom flip**

### Waveform

- **AUTO / UI (default)** — uses `Screen:refreshUI()` for each reveal step. On Kindle Rex this is KOReader's AUTO/UI waveform path.
- **DU / Fast** — uses `Screen:refreshFast()`.
- **A2** — uses `Screen:refreshA2()`. Very fast on PW4 but can produce more ghosting.

### Scheduling

- **Free-running (default)** — submit a reveal step, then wait the configured delay.
- **Fixed interval** — target absolute step times from the start so rendering/submit overhead does not accumulate.

### Strip delay

Available values: 0, 5, 10, 20, 30, 40, 50, 60, 80, and 100 ms. **40 ms** is the default.

### Full clean refresh afterwards

Disabled by default.

- **Off:** after the six reveal updates, restore the exact destination and perform a full-screen `refreshUI()` / AUTO settle.
- **On:** restore the exact destination and call full-screen `refreshFull()` instead. This is intended for aggressive modes such as A2 when ghost cleanup matters more than the extra latency or visible flash.

## Menu

1. **Animate normal page turns**
2. **Page-turn animation settings**
   - Reveal shape
   - Waveform
   - Scheduling
   - Strip delay
   - Full clean refresh afterwards
3. **Test animated next page**
4. **Test animated previous page**
5. **update plugin**

## Normal navigation

KOReader still handles taps, swipes, page-turn keys, RTL/inverse reading order, and document navigation normally. Page Turn Animation only records the direction for eligible one-page turns and performs the transition later in the framebuffer repaint lifecycle.

Internal `no_page_turn` calls and multi-page jumps are left alone.

## Self-update

**update plugin** remains the final menu item. It updates only `page-turn-animation.koplugin` from this repository's `main` branch, verifies revision/blob integrity, syntax-checks downloaded Lua, stages the replacement, retains a rollback backup, and offers to restart KOReader.
