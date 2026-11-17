# Contributing to glasser

Bug reports and pull requests are welcome. User documentation is in
[README.md](README.md); this file is about working on the code.

## Ground rules

- **bash 3.2.** macOS ships bash 3.2 as `/bin/bash`, and glasser must run
  on it: no associative arrays, no `${var,,}` / `${var^^}`, no `mapfile`,
  integer timeouts only in `read -t`. Prefer functions that set a global
  over `$(…)`: every command substitution is a fork.
- **BSD and GNU tools.** The script and the tests must work with the macOS
  (BSD) and the Linux (GNU) userland: no `sed -i` without a backup suffix
  in glasser, no GNU-only flags. Debian's default `awk` is mawk, which
  does not know UTF-8: put a multibyte character in a group before a
  quantifier, `(─){78}`, not `─{78}`.
- **Checks.** `make lint` (shellcheck) and `make test-all` must pass. If
  you change anything terminal- or platform-related, run the suite on
  Linux too (a Debian container with `libimage-exiftool-perl`, `expect`,
  `tmux`, `make` and a UTF-8 locale is enough; run it as a non-root user).

## Adding a camera

Cameras are built into the script: one `add_camera` line in
`load_camera_db` (the format is in README, [Database](README.md#database)).
A MakerNote group other than `Nikon` / `FujiFilm` / `""` also needs its
tags in the exiftool command (`build_exiftool_args`) and a test with a
real sample from that camera.

## Translations

The interface is English; translations live in `locale/<lang>.sh` next to
the script and are picked by `GLASSER_LANG` or by the first two letters
of the locale (`ru_RU.UTF-8` → `ru`). A language without a catalog file
falls back to English.

- **Keys are the English strings.** Every UI string in glasser is a
  literal in single quotes right after `_t`, `_tv VAR`, `tprintf`, `errf`
  or `dief`, on the same line, with no apostrophes. The test "Localization:
  catalog covers every UI key" extracts these literals and compares them
  with the catalog: a new or changed English string needs its translation
  in every catalog, and a removed one must be removed there too.
- **printf formats.** A key may be a printf format; the translation must
  keep every `%s` / `%d` in the same order (bash printf has no positional
  arguments).
- **New language:** copy `locale/ru.sh` to `locale/<lang>.sh`, rename the
  functions to `_l10n_<lang>`, `_plural_<lang>`, `_help_<lang>` and
  translate. `_plural_<lang>` receives the count and the English singular
  and plural (`file files`, `group groups`) and prints the noun form;
  `_help_<lang>` prints the `--help` text.

## Tests

```bash
make test            # /bin/bash ./run-tests.sh
make test-all        # once more — under the bash in PATH
make test-terminal   # + a real Terminal.app (opens windows on screen)
```

The tests read `tests/lenses.ini` (via `GLASSER_LENS_DB`), not your
personal `lenses.ini`: 28 real lenses with made-up serials. Test
expectations depend on its contents and order — edit it together with
`run-tests.sh`.

The suite copies the samples from `samples/` into temporary folders (all
inside one `glasser-test.*` in `$TMPDIR`, removed by an EXIT trap,
including on Ctrl-C), runs `glasser` and checks the key tags. The samples
are a read-only reference; the script never runs on the originals. Without
the required samples (`Fuji + Konica`, `Nikon + Primoplan`: JPG and RAW) it
exits immediately with code 2.

`glasser` is run through `GLASSER_BASH` (default `/bin/bash`, the target
bash 3.2), not through its `env bash` shebang: otherwise, with Homebrew
bash first in PATH, the tests would run under bash 5 and 3.2 regressions
would slip through. `GLASSER_BASH=bash` runs with the first bash in PATH.

The tests run with the English interface (`GLASSER_LANG=en`) regardless of
the locale. Two localization checks cover the rest: every UI key in
`glasser` has a translation in `locale/ru.sh` (and the catalog has no stale
keys), and the Russian interface and language selection work.

Result: `Pass / Fail / Skip`. A skip (not a pass) happens when the optional
sample `Nikon + Primoplan (unedit)` is missing, there is no `expect`, no
`tmux` (real-terminal tests), `GLASSER_LOAD_N=0`, or Terminal.app is not
enabled (its tests run only with `GLASSER_TERMINAL_APP=1`).

What is covered:

- **Auto-detection**: Fuji X-T4 + Hexanon (crop 1.5; the test database has
  a single 57 mm lens — `hexanon-57-14`), Nikon Z f + Primoplan (crop 1.0,
  Nikon quantization `58 → 58.2 mm`; a single 58 mm lens in the database —
  `biotar-58`); tags are checked in both JPG and RAW (RAF / NEF).
- **Cross**: Nikon Z f + Hexanon — the camera ↔ lens pairing is
  decoupled, Nikon tags are written with Konica data (quantization
  `57 → 56.6 mm`).
- **Idempotency**: a second run over an already tagged folder succeeds
  and does not change the key tags (separately for Fuji and Nikon).
- **detect_lens**: step 2 — matching by `FocalLength` when `LensModel` is
  empty; tie-break by `LensInfo` when `MaxApertureValue` is empty (50/1.9 →
  Xenon, 50/2 → Nikkor-H).
- **Raw Nikon** with an adapter profile of 50/1.5: the guess from the
  adapter profile is not the truth, so the test checks the override
  `--lens biotar-58`.
- **Multi-group**: 2 groups (no cross-contamination) and 3 groups (plan
  + summary).
- **`--dry-run` multi-group**: code 0, file md5s unchanged, one `exiftool`
  command per group in the output.
- **Serials**: re-tagging with a lens without a serial erases the old
  `LensSerialNumber`; the body serial in `XMP-aux:SerialNumber` is not
  erased.
- **Database**: an unknown MakerNote group in `add_camera` is an error at
  load time.
- **Commit-phase atomicity**: with `--no-confirm`, group 1 guessed, group 2
  not: code 1, no file changed.
- **Many files in one group**: a smoke test on N copies (`GLASSER_LOAD_N`,
  default 5). The `-@ argfile` path is nothing special for it — every run
  uses it.
- **Scan parsing**: an empty `LensModel` does not shift the fields of the
  `EXIF:` line; a `#roll` folder given as a relative path; a file name with
  a newline does not get into the `-@ argfile`.
- **Ambiguous lens** (50/1.2) — an error with `--no-confirm`; a unique one
  (50/1.9) is guessed.
- **exiftool error in a group** (a file in a read-only folder) — the other
  groups are written, summary "with errors", code 1.
- **Arguments**: `--help` / `--version` / `--list-*` — code 0; unknown
  option, `--camera` / `--lens` without an id, not a folder, empty folder,
  extra argument (including `d3 -- d4`) — code 1 with a message; an invalid
  `--lens` / `--camera` — an error before scanning; a folder where all
  files are filtered out (TAB in the path) — code 1 with the reason and the
  number skipped.
- **`LC_ALL=C`**: the tables are the same as under UTF-8.
- **No terminal** (via `setsid`) and no `--no-confirm` — code 1.
- **Interactive** (via `expect`, if present): `s` skips a group (its file
  untouched, the second one tagged); `n` at "Apply the plan?" and `q` —
  code 0, "Cancelled", files unchanged; Ctrl-D — code 1, files unchanged.
- **Menu**: input with a leading zero is decimal; `0` in the menu returns
  to "Accept?". The tests take item numbers and the "0..N" range from the
  database (`--list-cameras`, `--list-lenses`; helpers `camera_menu_pos`,
  `camera_menu_count`, `lens_menu_pos`) instead of hardcoding them: new
  cameras and lenses do not break them.
- **Card mode** (stdin, stdout and stderr on a 40×100 pty; the expect
  script works as a small terminal emulator: it keeps a screen and answers
  CSI 6n with the real cursor position). Both the tags and the screen
  itself are checked: confirming a single group (banner instead of the scan
  phase, progress bar); the splash on 40 rows (drawing, f/1.2–16 ring,
  caption, aperture frames during the scan, "shutter click") and the styled
  card (indent, rule, EXIF by field, check marks, keys on one line; headers
  "◉ Group N of 2", summary after a correction without check marks); with
  `NO_COLOR` — not a single SGR; on 29 rows and with `--no-art` — the
  banner line; the splash when the screen is redrawn after an overflow;
  two groups with correction through the menu (the lens menu does not fit —
  redraw after overflow; the header is not duplicated; the plan screen
  shows the banner and the collapsed lines once each, with no leftover
  cards); `0` in the menu — back, `s` — skip, `q` — cancel. Short screens:
  17 rows — the card at the bottom edge, the screen scrolls in advance;
  12 rows — the card does not fit from the start (redraw, the header is not
  duplicated); 9 rows with `--no-confirm`. A terminal that does not answer
  CSI 6n — exactly one query, a wait of no more than ~1 s, linear output
  with no erasing, the write runs to the end. Every scenario must use up
  all prepared answers: if glasser exits before reaching the last prompt,
  that is an error (code 97), not a pass.
- **Real terminal** (via `tmux`, if present; without it the tests are
  skipped): cards at 16×100 and 24×80 — tags, the last screen and the
  whole scroll-back with no leftover cards or scan phase; correction
  through the menu at 24×80 — tags, the screen after the redraw (banner,
  collapsed group 1 and the header of group 2 — once each, menu erased)
  and the scroll-back: the menu itself scrolls the top of the card into
  it, so exact counts are checked there — one copy each of the header and
  EXIF, no tail of the menu (the "0) Back" item), no prompts ("Accept?",
  "Number ["), no scan phase (the start of the lens menu going into the
  scroll-back is expected). tmux runs on a separate socket
  (`-L glasser-test-…`) and is shut down after the test; the regular tmux
  server is not touched. glasser does not start erasing with ED at home:
  tmux (and other terminals) would push such a screen into the scroll-back.
- **Terminal.app** (only on request: `GLASSER_TERMINAL_APP=1
  ./run-tests.sh` or `make test-terminal`; otherwise skipped with the
  reason): the same two scenarios as in tmux, in a new Terminal.app window
  ("Basic" profile, 16×100 and 24×80; the size is checked with
  `stty size`). Answers are sent by `osascript` (`do script … in tab` —
  text and Enter into the tab's input), the screen and scroll-back are the
  tab's `contents` and `history` properties; the widths of glasser's glyphs
  (◉ ○ ◎ ✓ ━ █ ▒ ╭ ┴ ∞ ← · …) are also measured via the CSI 6n answer — all
  must take 1 column. Needs the "Automation → Terminal" permission for the
  app the run is started from (Accessibility is not needed); without it —
  a failure with a hint after 30 s, not a hang. Only the window the test
  opened is closed (by id), including on failure and Ctrl-C; if the run
  launched Terminal.app itself and there are no other windows, it quits.
  Terminal.app behaved the same as tmux and the emulator: erasing from home
  without ED 2 does not reach the scroll-back, glyphs take 1 column.
- **Ctrl-C** (via `expect`, a stub `exiftool`): in `--dry-run` — immediate
  exit with code 130, with no timing race (a stub `awk` holds the path
  output until Ctrl-C arrives); in the middle of writing group 1 — code
  130, "interrupted", group 2 is not written; while waiting for the CSI 6n
  answer — glasser dies from SIGINT (rather than just exiting with code
  130), tty settings (`stty -g`) are restored; during the scan spinner —
  code 130, the spinner line is erased, the pty closes immediately (the
  background spinner does not outlive glasser).
- **Splash aperture ring** (number layout) for the range of every lens in
  the database: exactly 23 columns, numbers descending, the widest aperture
  on the right, none greater than the minimum aperture. The other tests run
  with `GLASSER_NO_ART=1`: seven lines of drawing would get in the way of
  the line-by-line comparison of card screens.

## Layout

```
glasser           main script (executable, bash 3.2)
run-tests.sh      tests (list — run_case in main)
locale/ru.sh      Russian interface (_l10n_ru, _plural_ru, _help_ru)
README.md         documentation in English
README.ru.md      documentation in Russian
CONTRIBUTING.md   this file
LICENSE           MIT
lenses.example.ini  lens database template (copy → lenses.ini)
lenses.ini        personal database (not in git)
tests/lenses.ini  test database for run-tests.sh
Makefile          install / uninstall / test / lint
samples/          reference JPG+RAW pairs for tests (read-only)
  Fuji + Konica/
  Nikon + Primoplan/
  Nikon + Primoplan (unedit)/   untouched photo with an adapter profile
```
