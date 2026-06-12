# README demo GIF — capture plan

The README header has a commented-out `<img>` placeholder for `docs/assets/demo.gif`. This is the plan for recording it. Target: ~10 seconds, under ~5 MB, autoplaying GIF committed to the repo.

## Why a GIF (not a screenshot or MP4)

The product is the motion — summon, arrow, paste — which a screenshot can't show. A GitHub-uploaded MP4 would be smaller and sharper but renders as click-to-play and isn't version-controlled. A GIF autoplays inline on the repo page. If the tuned GIF still exceeds ~5 MB, reconsider the MP4 user-attachment; it's a one-line README swap.

## Storyboard (~10 s)

1. TextEdit open, cursor blinking in an empty document.
2. Press **⌘⇧V** — overlay slides up showing the seeded cards.
3. Pause ~1 s (let the viewer read the cards).
4. Arrow right twice.
5. **Enter** — overlay dismisses, text appears in TextEdit.
6. Hold ~1 s on the pasted result, stop recording.

Keep it to summon → navigate → paste. Search can be a second GIF later; don't crowd this one.

## Seed the history

Copy from Terminal (oldest first) so cards get distinct types and a source icon:

```sh
printf 'Ship the keyboard-first overlay' | pbcopy && sleep 1
printf 'let item = ClipboardItem(.text)' | pbcopy && sleep 1
printf 'https://github.com/jtreanor/recall' | pbcopy && sleep 1
printf 'Standup notes: demo Recall GIF' | pbcopy && sleep 1
```

The third item exercises the URL badge.

## Record

Use the real hotkey — with Accessibility already granted, no code changes are needed. (For scripted, repeatable takes, the Darwin-notification toggle harness from PR #40 — `notifyutil -p com.recall.debugToggle` — can drive open/close without the hotkey; see plan.md git history at commit `49e8bfb`. Overkill for a one-off manual recording.)

```sh
# Record the bottom region of the screen: overlay is bottom-anchored;
# keep the TextEdit window in frame. Adjust the rect to your display.
screencapture -v -R0,400,1440,500 demo.mov
# Ctrl-C in that terminal to stop and finalize the file.
```

## Convert

```sh
ffmpeg -i demo.mov \
  -vf "fps=15,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer" \
  -loop 0 docs/assets/demo.gif
```

If over ~5 MB: drop to `fps=12`, `scale=800`, or trim dead frames with `-ss`/`-t`.

## Publish

1. Commit `docs/assets/demo.gif`.
2. Uncomment the placeholder `<img>` block in `README.md`.
3. Tick the GIF checkbox in `docs/plan.md` Phase 8 and delete this file.
