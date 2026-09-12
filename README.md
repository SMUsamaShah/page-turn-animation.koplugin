# Page Turn Animation for KOReader

A KOReader plugin that animates normal page turns on E-Ink devices, currently tuned and tested around the Kindle Paperwhite 4 / Rex display path.

The installable plugin folder is `page-turn-animation.koplugin`. Its KOReader plugin ID is `pageturnanimation`.

Version **0.1.0** uses a fast six-step reveal and supports several page-like edge shapes without a heavyweight curl renderer.

## Features

- Animate normal one-page taps, swipes, and page-turn keys.
- Straight, diagonal, or curved-bottom reveal shapes.
- AUTO/UI, DU/Fast, or A2 refresh waveform.
- Free-running or fixed-interval scheduling.
- Configurable step delay from 0 to 100 ms.
- Optional full clean refresh after the animation.
- Built-in self-update from this repository.

## Known-good default

- Straight vertical
- AUTO / UI
- Free-running
- 40 ms
- Full clean refresh afterwards: off
- 6 temporal steps

## Installation

Copy `page-turn-animation.koplugin` into KOReader's `plugins` directory and restart KOReader.

## How it works

For an eligible one-page turn, KOReader performs navigation and renders the destination page normally. Page Turn Animation snapshots the old framebuffer before paint and captures the completed destination framebuffer before the first physical refresh. It then reveals the destination in six steps, restores the exact destination framebuffer, and performs the final settle refresh.

## Self-update

The final menu entry, **update plugin**, updates `page-turn-animation.koplugin` from this repository's `main` branch, verifies revision/blob integrity, syntax-checks downloaded Lua, stages the replacement, retains a rollback backup, and offers to restart KOReader.
