# Dice & Life

Life counters and dice for tabletop games (Magic: The Gathering and others) on
the reMarkable Paper Pro family, as an [AppLoad](https://github.com/asivery/rm-appload) app.

- **Life**: 1 to 4 players starting at 20, 25, 30 or 40. Tap the left half of a
  player's panel to lose 1 life, the right half to gain 1, or use −5 and +5.
  Players across the table get upside-down panels, and each panel shows what
  the last few taps added up to.
- **Dice**: a coin, d4, d6, d8, d10, d12, d20 and d100, 1 to 5 at a time, with
  the total and the previous rolls. Each roll is numbered, so rolling the same
  result twice still visibly changes the screen.

Life totals and rolls are saved in `~/.local/share/dice/state.json`, so a game
survives closing the app. The backend (`backend/`) only does that saving; the
frontend is `ui/main.qml`.

## Building

In `nix develop` (from [nix-remarkable-sdk](https://github.com/cyprienruffino/nix-remarkable-sdk)):

```sh
# On the PC, with the backend
cmake -B build-pc -G Ninja && cmake --build build-pc
cmake --install build-pc --prefix dist-pc/dice
appload-run dist-pc/dice

# On the tablet
cmake -B build-rm -G Ninja -DCMAKE_TOOLCHAIN_FILE=$RM_TOOLCHAIN_FILE && cmake --build build-rm
cmake --install build-rm --prefix dist/dice
rm-deploy dist/dice
```
