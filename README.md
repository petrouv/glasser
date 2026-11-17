**English** · [Русский](README.ru.md)

# glasser

Rewrites lens EXIF/XMP/MakerNote tags for photos taken with manual lenses
on adapters. After import, one command replaces everything lens-related
with the real data from its database.

Where the "wrong" lens information in EXIF comes from — cases that are not
tied to a particular system:

- **Electronic (smart) adapter** (e.g. Shoten LM-Z E for Nikon Z). The
  adapter reports the selected profile (focal length + aperture) to the
  camera, and the camera writes it to EXIF as a "native" lens. The adapter
  itself does not know which lens is actually mounted — the user picks the
  profile on it by hand.
- **Mechanical adapter ring** with no electronics. Exists for any mount
  (Nikon, Fuji, Sony, etc.). The camera knows nothing about the lens; EXIF
  gets either garbage/nothing or whatever the user entered in the camera's
  "non-CPU lens data" / "Mount adapter" menu (focal length and maximum
  aperture — usually for IBIS and metering).
- **Manual entry** of a lens profile in the camera menu on any system —
  even without an adapter, if the lens is chipless on its native mount.

In every case the correct lens identification has to be set after the
fact — that is what `glasser` is for.

## Quick start (macOS)

Step by step, for those who rarely use the terminal. On Linux it is the
same without Homebrew; on Windows, use WSL (see
[Installation](#installation)).

Supported cameras: Nikon Z f, Fujifilm X-T4, X-E5 and X-E3. Another
camera needs one line in the script (see [Database](#database)).

1. Open **Terminal** (Spotlight: ⌘ Space, type "Terminal").
2. Install [Homebrew](https://brew.sh): copy the install command from its
   page into Terminal and press Enter. Then install exiftool:
   ```bash
   brew install exiftool
   ```
3. Download glasser: on GitHub, **Code → Download ZIP**, and unpack it, for
   example into Documents. In Terminal type `cd ` (with a space), drag the
   unpacked folder from Finder into the Terminal window, press Enter.
4. Create your lens list and open it in TextEdit:
   ```bash
   cp lenses.example.ini lenses.ini
   open -e lenses.ini
   ```
   Replace the example lenses with yours (the format is described at the
   top of the file and in [Database](#database)) and save.
5. Install the `glasser` command and make it findable (once):
   ```bash
   make install
   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zprofile
   ```
   Close Terminal and open it again.
6. **glasser rewrites the photos in place, without backups.** Try it on a
   copy of a folder first. Type `glasser ` (with a space), drag the folder
   with the photos into the window, press Enter. For each group of photos
   glasser shows the camera and lens it guessed: Enter accepts, `n` lets
   you pick from a list. At the end it shows the plan and asks once more
   before writing anything. `glasser --dry-run <folder>` shows what would
   be written without touching the files.

## Installation

Requirements: bash, exiftool (`brew install exiftool`).

```bash
cp lenses.example.ini lenses.ini   # and fill in your lenses
make install        # symlink in ~/.local/bin/glasser
make uninstall      # remove it
make                # help
```

`~/.local/bin` must be in `PATH`; macOS does not add it by default (see
[Quick start](#quick-start-macos), step 5).

Platforms: **macOS** — tested (bash 3.2 and 5). **Linux** — the test suite
passes on Debian 13 (bash 5.2); exiftool comes from the distribution
(`sudo apt install libimage-exiftool-perl` on Debian/Ubuntu). **Windows** —
through WSL (Linux inside Windows): not tested, but it is the same Linux
environment; Windows drives are under `/mnt/c/…`. Git Bash and plain
Windows (cmd, PowerShell) are not supported.

A symlink, so that edits to `lenses.ini` and `load_camera_db` are picked up
without reinstalling. The script looks for `lenses.ini` next to its real
file (the symlink is resolved), so there is no need to copy it to
`~/.local/bin`. A different database file: `GLASSER_LENS_DB=path`.

`lenses.ini` is your personal database and stays out of git
(`.gitignore`); the repository holds the template `lenses.example.ini` and
the test database `tests/lenses.ini`.

## Interface language

glasser prints English by default. Russian is used when the locale
(`LC_ALL`, then `LC_MESSAGES`, then `LANG`) starts with `ru`;
`GLASSER_LANG=en` or `GLASSER_LANG=ru` sets the language explicitly and
overrides the locale. Screen output quoted below is the English interface.

The Russian strings live in `locale/ru.sh` next to the script; like
`lenses.ini`, glasser looks for it next to its real file, so a symlink
install works. It is a bash file with three functions: `_l10n_ru` (English
string → Russian), `_plural_ru` (noun form for a count) and `_help_ru`
(the `--help` text). The keys are the exact English strings from
`glasser`, `%s` / `%d` included; a missing translation falls back to
English. Without a `locale/<lang>.sh` file the whole interface is English.

Adding a language: see [CONTRIBUTING.md](CONTRIBUTING.md#translations).

## Usage

```
glasser                       process the current folder (with subfolders)
glasser PATH                  process the given folder (with subfolders)
glasser --list-lenses         lens table
glasser --list-cameras        camera table
glasser --dry-run [PATH]      show the command, write nothing
glasser --no-confirm [PATH]   non-interactive (use the guesses)
glasser --camera ID [PATH]    force this camera
glasser --lens   ID [PATH]    force this lens
glasser --verbose [PATH]      per-file progress instead of a progress bar
glasser --no-art [PATH]       no splash, spinner or animation
glasser --version             version
glasser --help                help
```

The folder is scanned **recursively**, with all its subfolders. Handled
extensions: `jpg`, `jpeg`, `nef`, `raf`, `tif`, `tiff`, `dng`, `arw`,
`cr2`, `cr3` (case-insensitive). Running in a parent folder affects the
photos in all nested ones.

`--camera` / `--lens` apply to **every** group in the folder (see
"Grouping") — both interactively and with `--no-confirm`.

While writing (in card mode, see "UI in a TTY and in a pipe") a progress
bar is shown as a single updating line:

```
[████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░]  30% (24/80) _DSC0042.NEF
```

With `--verbose`, or outside card mode (output redirected to a file/pipe,
`TERM=dumb`, the terminal did not answer the cursor position query), the
bar is replaced by exiftool's per-file output, one line per file:

```
======== /path/_DSC0042.NEF [24/80]
```

## Flow

Files are written in **two phases**: first the decisions for all groups
are collected (commit), then the plan is applied with one command (apply).
**Nothing is written** before the plan is applied: if you change your mind
at the final question you can cancel, and nothing has been written. The
write itself is not transactional: exiftool writes file by file. If
exiftool returns an error on some group (locked file, no permission, disk
full), the remaining groups are still processed, the failed group is
marked "failed" in the final summary (some of its files may have been
written), and the exit code is 1. Ctrl-C during the write stops the run
after the current exiftool call: the current group may be partly written,
the following ones are untouched, exit code 130. Re-running is safe:
already tagged files get the same values.

```
1. Scan the folder (batch exiftool, reads Make/Model/Lens*/Focal*/MaxAp)
2. Group by signature (one camera + one lens = one group)
3. Commit phase, for each group:
     • guess camera + lens (or ask to choose)
     • ask: Accept?   Y accept   n change   s skip   q quit
4. Apply phase:
     • overall plan + tag preview for each group
       (exactly what goes into EXIF)
     • ask: Apply the plan? [Y/n]
     • exiftool writes the files group by group
5. Final summary.
```

Prompts:

| Where | Options | Meaning |
|---|---|---|
| Commit (per group) | `Y` / `n` / `s` / `q` | `Y` accept, `n` change (camera→lens), `q` quit, `s` skip the group |
| Camera/lens menu | number | `Enter` keeps the current choice; `0` goes back to "Accept?" with the previous choice (`0) Back`), or, if not everything was guessed and there is nothing to go back to, skips the group (`0) Skip group`). Quitting everything is only `q` |
| Apply (once) | `[Y/n]` | `Y` apply the whole plan, `n` cancel (nothing written) |

With `--no-confirm` both interactive prompts are skipped, but the plan with
the tag preview is still printed — for transparency. Without a terminal
(cron, CI, pipe) interactive mode does not start: without `--no-confirm`
glasser exits immediately with the error "no terminal — use
--no-confirm", before scanning. This applies to `--dry-run` as well — it
also asks per group.

Exit codes:

- `0` — done, or cancelled by the user (`q`, `n` at "Apply the plan?"), or
  all groups skipped;
- `1` — error: no `lenses.ini` or an error in it (message with the line
  number), invalid arguments or ids in `--camera`/`--lens` (checked before
  scanning), no images in the folder (or all found ones skipped — the
  reason and count are in the message), not guessed or ambiguous with
  `--no-confirm`, no terminal, Ctrl-D (EOF) at a prompt or in a menu with
  no guessed value (in a menu with a guessed value Ctrl-D = Enter), an
  exiftool error in at least one group;
- `130` — interrupted by Ctrl-C: before writing (prompts, `--dry-run`)
  nothing is written; during the write the current group may be partly
  written, the following ones are untouched.

### UI in a TTY and in a pipe

Card mode is on only when all three conditions hold:

1. **stdout** is a terminal (`-t 1`); stderr and stdin are not checked;
2. `TERM` is set and is not `dumb`;
3. the terminal answered the cursor position query (CSI 6n) — glasser asks
   once at startup and waits up to 1 s.

Otherwise the output is linear. Prompts and menus go to **stderr**, answers
are read from `/dev/tty`. So `glasser >log` gives a linear log with the
prompts on screen, while `glasser 2>log` keeps the cards but sends prompts
and menus to the file. Interactive mode needs an openable `/dev/tty` (see
above); without one, only `--no-confirm`.

- **Card mode**: the screen is cleared (scroll-back is kept), a banner
  `◉ glasser · <folder> · N files` at the top, each group is a "card"
  redrawn in place. When you go from the prompt to the correction menu and
  back, the content is redrawn in the same spot, with the card header as
  the anchor. On `Y`/`s` (and with `--no-confirm` after a successful guess)
  the card collapses into a one-line summary.
- **Linear mode** (pipe, stdout redirected to a file, cron, `TERM=dumb`, a
  terminal that does not answer CSI 6n): no redraws, no screen clearing, no
  erasing. Cards become a plain linear log; everything shown stays, and the
  group's summary line is printed below.

#### Splash and animation

In card mode on a screen of at least 30×66, the banner line at the top is
replaced by a splash: a lens with a distance scale, a knurled focus ring
and an f/1.2–16 aperture ring, with a caption on the right (name, folder
and number of files / groups). The aperture numbers use muted colors, like
on old lenses (readable on both light and dark backgrounds). On a smaller
screen it is the usual line `◉  glasser  ·  <folder>  ·  N files`.

The group card is styled too: everything indented by 2 columns, a header
`◉ Group 2 of 4 · 3 files`, a thin rule, a dim EXIF line wrapped by field,
a summary with check marks `✓ detected` / `✓ guessed` (anything not guessed
gets an amber `?`), the lens generation and serial on a separate line, the
keys `Y n s q` on one line below the question.

While exiftool starts, an aperture spinner `· ○ ◎ ◉ ◎ ○` turns
("Scanning…"), then the same frame stays in front of the scan progress
line. At the end, before `✓ Done.`, comes a "shutter click" (the aperture
closes and opens, only if stdout is a terminal).

`--no-art` or `GLASSER_NO_ART=1` turn all of this off (banner line, the
plain card with `EXIF:` and `[Y] accept`, no spinner or click). Outside
card mode (pipe, file, `TERM=dumb`) the output is plain too. `NO_COLOR`
(any non-empty value, [no-color.org](https://no-color.org)) keeps the
drawing but without color.

## Grouping

On start the folder is **always** scanned first with one batch `exiftool`
command, reading `Make + Model + LensModel + FocalLength +
MaxApertureValue`, and the files are grouped by this signature. Then the
script goes through the groups one by one, each with the usual flow (guess
→ confirm / correct → write only to this group's files).

Why: protection against mixes. If the folder contains photos from two
cameras or with different lenses, they end up in different groups and each
gets its own tags. If a single photo from another camera slipped into the
folder, it becomes a separate group of 1 file; press `s` (skip) to leave it
alone.

The confirmation prompt lists its keys after the question:

```
Accept?   Y accept   n change   s skip   q quit
```

Without cards (pipe, `TERM=dumb`) or with `--no-art` the keys go on
separate lines: `[Y] accept`, `[n] change`, `[s] skip group`,
`[q] quit`. `Y` (or Enter) writes the group, `n` corrects the choice, `s`
skips the group and goes to the next one, `q` quits.

`--camera ID` / `--lens ID` replace the guess in **all** groups at once
(interactively the choice can still be corrected with `n`). With
`--no-confirm` a successful guess (or these overrides) is required for
**every** group; otherwise it is an error naming the group that was not
guessed, and no file is written.

## Database

Lenses live in `lenses.ini` next to the script; cameras are hardcoded in
the `load_camera_db` function in the script itself.

**Lens** — a section in `lenses.ini`:

```ini
[jupiter-9]
make        = Jupiter
model       = 9 85mm f/2
display     = Юпитер-9 85мм f/2
focal       = 85
max         = 2
min         = 16
serial      =
lens_string = 85mm f/2
generation  = белый
```

- `[id]` — what you pass to `--lens`; unique, no whitespace.
- `model` — without the brand, `display` — the full name with the brand.
- `max`, `min` — maximum and minimum aperture (f-numbers).
- `lens_string` — short form for `Nikon:Lens`, e.g. `58mm f/1.9`.
- `generation` — a short revision/version marker to tell several copies of
  one model apart in the menu (`M-4`, `II`, `D`, `белый`, …). Not written
  to EXIF. If you have only one copy, leave it empty.
- `serial` and `generation` may be omitted entirely; the other keys are
  required. The value is everything after the first `=`, with surrounding
  whitespace trimmed; comments only as whole lines starting with `#`.
- Errors in the file (unknown or repeated key, missing required key,
  repeated id or whitespace in it, malformed line) stop the script before
  scanning, pointing to `lenses.ini:N`.

**Camera:**

```
add_camera "ID" "make_regex" "model_regex" "Display" \
           crop_factor "MakerNoteGroup" has_nikon_lens
```

`model_regex` must be `^...$`, otherwise `Z f` matches `Z fc`.
`MakerNoteGroup` ∈ {`Nikon`, `FujiFilm`, `""`} (any other value is an error
when the database loads). `has_nikon_lens` (`true`/`false`) — whether to
write a separate `Nikon:Lens` tag.

## What is written

| Tag | Why |
|---|---|
| `LensMake`, `LensModel`, `LensSerialNumber` | Standard, read by everything |
| `LensInfo` | `Focal Focal MaxAp MaxAp` (see below) |
| `MaxApertureValue`, `FocalLength`, `FocalLengthIn35mmFormat` | Lens properties |
| `XMP-aux:Lens`, `XMP-aux:LensSerialNumber` | For Adobe |
| `XMP-exifEX:LensMake`, `LensModel`, `LensSerialNumber`, `LensInfo` | Modern equivalent; `LensInfo` is exiftool's name for the XMP property `exifEX:LensSpecification` (see "The `-EXIF:` group for LensInfo is required") |
| `Nikon:MinFocalLength`, `Nikon:MaxFocalLength`, `Nikon:MaxApertureAt{Min,Max}Focal`, `Nikon:Lens` | For NX Studio |
| `FujiFilm:MinFocalLength`, `FujiFilm:MaxFocalLength`, `FujiFilm:MaxApertureAt{Min,Max}Focal` | For X RAW Studio |

## What is **not** written

- `FNumber`, `ApertureValue` — per-shot, not lens-level.
- `LensType`, `LensIDNumber`, `AF Aperture`, `Effective Max Aperture`,
  `Lens Mount Type` — runtime flags of an electronic adapter, not read in
  post-processing (with mechanical adapters and manual entry they simply
  do not exist).
- `Composite:LensID`, `XMP-aux:LensID` — computed or nonexistent in the
  standard; writing them is useless or breaks ValueConvInv.
  (`exifEX:LensSpecification` is written — via the name
  `XMP-exifEX:LensInfo`; exiftool does not accept the name
  `XMP-exifEX:LensSpecification`.)
- `XMP-aux:SerialNumber` — this is the **body** serial. Old versions of
  glasser wrongly wrote the lens serial there; on re-tagging that tag is
  erased, but only if it matches the old `ExifIFD:LensSerialNumber` and
  does not match `ExifIFD:SerialNumber`. A foreign value is left alone.

Lens serials are always written: if the database has no serial, the
`LensSerialNumber` tags are erased, so that re-tagging does not leave the
previous lens's serial behind.

## Pitfalls

### By the standard, LensInfo is not "wide open–stopped down"

`Exif 2.32 LensSpecification` is 4 rationals:

1. min focal
2. max focal
3. **min F-number** (= widest aperture) at min focal
4. **min F-number** (= widest aperture) at max focal

The third and fourth are both about the **widest** aperture, just at the two
ends of a zoom. For a prime both are equal: `57 57 1.2 1.2`. The smallest
aperture is **not written** to LensInfo — the spec has no place for it.

When reading, exiftool prints `57mm f/1.2` if values 3 and 4 are equal, and
`57mm f/1.2-X` if they differ. The everyday intuition "MinAperture = wide
open, MaxAperture = stopped down" leads to non-standard values and odd
strings like `57mm f/1.2-16` in catalogers.

The script's database still stores the `min_aperture` field, but it is
currently neither printed nor written anywhere — reserved for the future
(printing in `--list-lenses`, possibly writing to the MakerNote).

### Nikon quantizes the focal length in the MakerNote

Write `Nikon:MinFocalLength=58` and you read back `58.2 mm`; for 57 —
`56.6 mm`. This is not a bug: the Nikon format stores the focal length in
one byte on a non-linear scale, so not every whole millimeter is exactly
representable. The "convenient" points (24, 35, 50, 85, 105) land almost
exactly.

The standard `EXIF:FocalLength` (rational) stays an even `58.0`. RAW
converters read that one, not the Nikon MakerNote. Converters are not
affected.

### Composite:LensID is manufacturer-specific

It is a **computed** field that does not physically exist in the file;
exiftool synthesizes it on read.

- **Nikon:** a hash of 8 MakerNote bytes (`Nikon:LensIDNumber`, `LensType`,
  `LensFStops`, `Min/MaxFocalLength`, `MaxApertureAt{Min,Max}Focal`,
  `MCUVersion`) is looked up in a hardcoded table of ~500 Nikkors. For a
  manual lens (via an electronic adapter, a mechanical ring or manual
  entry) the hash is not in the table → **`Unknown (XX YY ...)`**.
  This is correct: avoiding it would mean faking the bytes of some real
  Nikkor, and NX Studio would try to apply someone else's correction
  profile. A manual lens is identified by `LensMake + LensModel`, which we
  write explicitly.
- **Fuji:** no hash table. exiftool builds Composite:LensID from the text
  `LensMake + LensModel` (falling back to XMP-aux/exifEX). So for Fuji
  Composite:LensID shows a readable name right after tagging.

### The `-EXIF:` group for LensInfo is required

The script writes `-EXIF:LensInfo=...` (with an explicit group), not just
`-LensInfo=...`. Without a group exiftool treats the tag as "unqualified"
and **duplicates** the write into every group where the tag is defined —
including an automatic write to `XMP-exifEX:LensSpecification`. Our
explicit `-XMP-exifEX:LensInfo=...` next to it is then added on top →
`rdf:Seq` gets 8 elements instead of 4, and this is not idempotent.

With an explicit group, `-EXIF:` writes only to EXIF and `-XMP-exifEX:`
only to XMP, both in one command, exactly 4 elements in the Seq. This is a
classic mistake from exiftool's
[Common Mistakes](https://exiftool.org/mistakes.html) — forgetting to give
the group for a tag that exists in several namespaces.

### `MaxApertureValue` vs `FNumber`

- `MaxApertureValue` — a lens property, the widest aperture.
  **We overwrite it.**
- `FNumber`, `ApertureValue` — properties of a particular shot. The camera
  puts garbage there for a manual lens. **We leave them alone** — they are
  per-shot, not lens-level.

### What auto-detection uses

The data comes from the first file of the group.

1. If `LensModel` in EXIF contains a model from the database, and
   `LensMake` is empty or also matches (re-tagging), it is taken from there.
2. Otherwise — match by `EXIF:FocalLength` (±0.5 mm — slack for a rounded
   or imprecise focal length from an adapter, chip or manual entry; Nikon's
   MakerNote quantization plays no part here, `EXIF:FocalLength` is even).
3. With several candidates — tie-break by `MaxApertureValue` (±0.05). If
   `MaxApertureValue` is empty, the f-number from `LensInfo` is used
   (`58mm f/1.9` → 1.9). If there is no aperture there either, there is no
   tie-break and the lens is not guessed.

If after step 1 (`LensModel` without `LensMake` matched several entries) or
step 3 (several candidates with the same aperture, e.g. 50/1.2 — Canon FD
50mm f/1.2 and FD 50mm f/1.2 L) more than one lens remains, it is **not
guessed**: with `--no-confirm` it is an error listing the candidates
("lens is ambiguous: canon-fd-50-12, canon-fd-50-12l — need --lens ID"),
interactively the menu opens right away. The first matching database line
is never taken silently. A single candidate by focal length is taken
without checking the aperture (see below).

`MaxApertureValue` from EXIF **cannot** be trusted as the primary
criterion: it holds either the electronic adapter's profile value, or
`1.0` / `undef`, or whatever the user entered in the camera menu — it has
no real correspondence to the lens.

## Contributing

Tests, code rules, translations and the repository layout:
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see `LICENSE`.
