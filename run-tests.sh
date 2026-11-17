#!/usr/bin/env bash
# Tests for glasser. The samples in samples/ are a read-only reference: the
# script works only on temporary copies (all inside one TEST_ROOT, removed
# by the EXIT trap, Ctrl-C included).
#
# The list of scenarios is the run_case calls in main (bottom of the file).
#
# glasser runs via GLASSER_BASH (default /bin/bash, the target bash 3.2 on
# macOS), not via its own `env bash` shebang: otherwise with Homebrew
# bash first in PATH the whole run would go under bash 5 and 3.2
# regressions (empty "${a[@]}" under set -u, fractional read -t …) would pass.
# GLASSER_BASH=bash runs with the bash that is first in PATH.
#
# Check return codes: 0 is success, SKIP_RC (77) is a skip (no optional
# sample, expect, tmux, GLASSER_LOAD_N=0 or Terminal.app not enabled),
# anything else is the number of errors (less than 77).
#
# Real Terminal.app (check_terminal_app_*) only on request:
# GLASSER_TERMINAL_APP=1 or `make test-terminal` (opens windows on the
# screen, needs the "Automation → Terminal" permission); without it the
# check is skipped with a reason.
#
# Menu item numbers and ranges ("enter 0..N") come from the database
# (lens_menu_pos, camera_menu_pos, camera_menu_count), not hard-coded:
# new database rows shift the numbers.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GLASSER="$SCRIPT_DIR/glasser"
BASH_BIN="${GLASSER_BASH:-/bin/bash}"
SKIP_RC=77

PASS=0
FAIL=0
SKIP=0
FAILURES=()

# Root for all temporary folders of the run (created by main).
TEST_ROOT=""

# glasser decoration (splash, spinner, "shutter click") is off by
# default: card checks compare the screen line by line, and the splash
# on a screen of 30+ rows would replace the banner line.
# Decoration is checked by dedicated tests (run_vt -a, check_banner_*).
export GLASSER_NO_ART=1

# Own lens database, not the personal lenses.ini: test expectations (ids,
# tags, serials, menu order) depend on its contents. tmux and Terminal.app
# get it explicitly (run_tmux, check_terminal_app_*).
export GLASSER_LENS_DB="$SCRIPT_DIR/tests/lenses.ini"
export GLASSER_LANG=en

# Runs glasser under the chosen bash (see the header).
run_glasser() {
    "$BASH_BIN" "$GLASSER" "$@"
}

# Removes the temporary folders of finished checks. chmod in case of an
# interrupted check_failed_group_continues (rm can't empty a read-only
# folder).
clean_cases() {
    [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]] || return 0
    chmod -R u+w "$TEST_ROOT" 2>/dev/null
    rm -rf "$TEST_ROOT"/case.*
}

cleanup_test_root() {
    tmux_kill
    ta_close
    [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]] || return 0
    chmod -R u+w "$TEST_ROOT" 2>/dev/null
    rm -rf "$TEST_ROOT"
}

# New empty temporary folder for a check; prints the path.
new_tmpdir() {
    mktemp -d "$TEST_ROOT/case.XXXXXX"
}

# Checks that a tag in the file has the expected value (as printed by
# `exiftool -s -s -s`; empty string means no tag).
check_tag() {
    local file="$1" tag="$2" expected="$3"
    local actual
    actual=$(exiftool -s -s -s "-${tag}" "$file" 2>/dev/null)
    if [[ "$actual" == "$expected" ]]; then
        return 0
    fi
    printf '  ✗ %s (%s): expected %q, got %q\n' "$tag" "$(basename "$file")" "$expected" "$actual" >&2
    return 1
}

run_case() {
    local name="$1"
    shift
    printf '\n=== %s ===\n' "$name"
    local errs=0
    "$@" || errs=$?
    if [[ $errs -eq 0 ]]; then
        printf '✓ %s\n' "$name"
        PASS=$((PASS+1))
    elif [[ $errs -eq $SKIP_RC ]]; then
        printf '⤳ %s (skipped)\n' "$name"
        SKIP=$((SKIP+1))
    else
        printf '✗ %s\n' "$name"
        FAIL=$((FAIL+1))
        FAILURES+=("$name")
    fi
    clean_cases
}

# Copies the sample folder to a temporary place and prints the copy path.
prepare_copy() {
    local src="$1"
    local tmp
    tmp=$(new_tmpdir) || return 1
    cp -R "$src/." "$tmp/"
    printf '%s\n' "$tmp"
}

check_fuji_konica() {
    local sample="$SCRIPT_DIR/samples/Fuji + Konica"
    local tmp
    tmp=$(prepare_copy "$sample")
    printf 'tmp: %s\n' "$tmp"

    run_glasser --no-confirm "$tmp" >/dev/null || {
        printf 'glasser failed\n' >&2
        return 1
    }

    local file="$tmp/_DSF1160.JPG"
    local errs=0
    check_tag "$file" LensMake          "Konica"                      || errs=$((errs+1))
    check_tag "$file" LensModel         "Hexanon AR 57mm F1.4"        || errs=$((errs+1))
    check_tag "$file" LensSerialNumber  "8143227"                     || errs=$((errs+1))
    check_tag "$file" LensInfo          "57mm f/1.4"                  || errs=$((errs+1))
    check_tag "$file" FocalLength       "57.0 mm"                     || errs=$((errs+1))
    check_tag "$file" FocalLengthIn35mmFormat "86 mm"                 || errs=$((errs+1))
    check_tag "$file" MaxApertureValue  "1.4"                         || errs=$((errs+1))
    check_tag "$file" "XMP-aux:Lens"    "Konica Hexanon AR 57mm F1.4" || errs=$((errs+1))
    check_tag "$file" "XMP-aux:LensSerialNumber" "8143227"            || errs=$((errs+1))
    # aux:SerialNumber is the body serial; a stray lens serial from the
    # sample's old tagging must be cleared.
    check_tag "$file" "XMP-aux:SerialNumber" ""                       || errs=$((errs+1))
    check_tag "$file" "FujiFilm:MinFocalLength"        "57"           || errs=$((errs+1))
    check_tag "$file" "FujiFilm:MaxFocalLength"        "57"           || errs=$((errs+1))
    check_tag "$file" "FujiFilm:MaxApertureAtMinFocal" "1.4"          || errs=$((errs+1))
    check_tag "$file" "FujiFilm:MaxApertureAtMaxFocal" "1.4"          || errs=$((errs+1))
    # Composite:LensID must be derived human-readable from make+model.
    check_tag "$file" "Composite:LensID" "Hexanon AR 57mm F1.4"       || errs=$((errs+1))
    # There must be no Nikon:Lens, since the camera is Fuji.
    local nikon_lens
    nikon_lens=$(exiftool -s -s -s -Nikon:Lens "$file" 2>/dev/null)
    if [[ -n "$nikon_lens" ]]; then
        printf '  ✗ Nikon:Lens must be absent, but: %q\n' "$nikon_lens" >&2
        errs=$((errs+1))
    fi

    # RAW (what the photographer keeps) is tagged by the same command.
    local raw="$tmp/_DSF1160.RAF"
    check_tag "$raw" LensModel                 "Hexanon AR 57mm F1.4" || errs=$((errs+1))
    check_tag "$raw" FocalLength               "57.0 mm"              || errs=$((errs+1))
    check_tag "$raw" "FujiFilm:MinFocalLength" "57"                   || errs=$((errs+1))
    check_tag "$raw" "FujiFilm:MaxApertureAtMinFocal" "1.4"           || errs=$((errs+1))

    return "$errs"
}

check_nikon_primoplan() {
    local sample="$SCRIPT_DIR/samples/Nikon + Primoplan"
    local tmp
    tmp=$(prepare_copy "$sample")
    printf 'tmp: %s\n' "$tmp"

    run_glasser --no-confirm "$tmp" >/dev/null || {
        printf 'glasser failed\n' >&2
        return 1
    }

    local file="$tmp/_DSC0020.JPG"
    local errs=0
    check_tag "$file" LensMake          "Carl Zeiss Jena"               || errs=$((errs+1))
    check_tag "$file" LensModel         "Biotar 58mm f/2"              || errs=$((errs+1))
    check_tag "$file" LensSerialNumber  "4471395"                          || errs=$((errs+1))
    check_tag "$file" LensInfo          "58mm f/2"                        || errs=$((errs+1))
    check_tag "$file" FocalLength       "58.0 mm"                           || errs=$((errs+1))
    check_tag "$file" FocalLengthIn35mmFormat "58 mm"                       || errs=$((errs+1))
    check_tag "$file" MaxApertureValue  "2.0"                               || errs=$((errs+1))
    check_tag "$file" "XMP-aux:Lens" "Carl Zeiss Jena Biotar 58mm f/2" || errs=$((errs+1))
    check_tag "$file" "XMP-aux:LensSerialNumber" "4471395"                 || errs=$((errs+1))
    # aux:SerialNumber is the body serial; a stray lens serial from the
    # sample's old tagging must be cleared.
    check_tag "$file" "XMP-aux:SerialNumber" ""                             || errs=$((errs+1))
    # Nikon quantizes the focal length: expect 58.2 mm on read.
    check_tag "$file" "Nikon:MinFocalLength" "58.2 mm"                      || errs=$((errs+1))
    check_tag "$file" "Nikon:MaxFocalLength" "58.2 mm"                      || errs=$((errs+1))
    check_tag "$file" "Nikon:MaxApertureAtMinFocal" "2.0"                   || errs=$((errs+1))
    check_tag "$file" "Nikon:MaxApertureAtMaxFocal" "2.0"                   || errs=$((errs+1))
    check_tag "$file" "Nikon:Lens" "58mm f/2"                             || errs=$((errs+1))
    # XMP-exifEX:LensInfo (Seq) must have exactly 4 items, not 8
    # (regression from EXIF↔XMP auto-sync when writing both at once).
    # With 4 items exiftool prints "58mm f/2", with 8 the raw string.
    check_tag "$file" "XMP-exifEX:LensInfo" "58mm f/2"                    || errs=$((errs+1))

    # RAW (what the photographer keeps) is tagged by the same command.
    local raw="$tmp/_DSC0020.NEF"
    check_tag "$raw" LensModel              "Biotar 58mm f/2"         || errs=$((errs+1))
    check_tag "$raw" FocalLength            "58.0 mm"                       || errs=$((errs+1))
    check_tag "$raw" "Nikon:MinFocalLength" "58.2 mm"                       || errs=$((errs+1))
    check_tag "$raw" "Nikon:Lens"           "58mm f/2"                    || errs=$((errs+1))

    return "$errs"
}

# Cross: set lens hexanon-57-14 on Nikon Z f shots.
# Check that Nikon tags are written correctly, but with Konica data.
check_cross_nikon_with_hexanon() {
    local sample="$SCRIPT_DIR/samples/Nikon + Primoplan"
    local tmp
    tmp=$(prepare_copy "$sample")
    printf 'tmp: %s\n' "$tmp"

    run_glasser --no-confirm --camera nikon-zf --lens hexanon-57-14 "$tmp" >/dev/null || {
        printf 'glasser failed\n' >&2
        return 1
    }

    local file="$tmp/_DSC0020.JPG"
    local errs=0
    check_tag "$file" LensMake          "Konica"                      || errs=$((errs+1))
    check_tag "$file" LensModel         "Hexanon AR 57mm F1.4"        || errs=$((errs+1))
    check_tag "$file" LensSerialNumber  "8143227"                     || errs=$((errs+1))
    check_tag "$file" LensInfo          "57mm f/1.4"                  || errs=$((errs+1))
    check_tag "$file" FocalLength       "57.0 mm"                     || errs=$((errs+1))
    # Nikon Z f has crop 1.0, so the equivalent = 57.
    check_tag "$file" FocalLengthIn35mmFormat "57 mm"                 || errs=$((errs+1))
    check_tag "$file" MaxApertureValue  "1.4"                         || errs=$((errs+1))
    check_tag "$file" "XMP-aux:Lens"    "Konica Hexanon AR 57mm F1.4" || errs=$((errs+1))
    check_tag "$file" "XMP-aux:LensSerialNumber" "8143227"            || errs=$((errs+1))
    # aux:SerialNumber is the body serial; a stray lens serial from the
    # sample's old tagging must be cleared.
    check_tag "$file" "XMP-aux:SerialNumber" ""                       || errs=$((errs+1))
    # Nikon tags are written even when the body is Nikon and the lens is not.
    check_tag "$file" "Nikon:MaxApertureAtMinFocal" "1.4"             || errs=$((errs+1))
    check_tag "$file" "Nikon:MaxApertureAtMaxFocal" "1.4"             || errs=$((errs+1))
    check_tag "$file" "Nikon:Lens" "57mm f/1.4"                       || errs=$((errs+1))
    # Nikon quantizes the focal length: 57 reads as 56.6 mm.
    check_tag "$file" "Nikon:MinFocalLength" "56.6 mm"                || errs=$((errs+1))
    check_tag "$file" "Nikon:MaxFocalLength" "56.6 mm"                || errs=$((errs+1))

    return "$errs"
}

# Idempotency: a second run must not change the key tags.
# Arguments: sample folder, file name for the LensModel check, expected
# LensModel, then the tags to compare (over all files of the copy, JPG and RAW).
# Both runs must succeed, and after the first one LensModel must be
# tagged: otherwise a run that wrote nothing (or failed on an already
# tagged folder) would give "before" == "after" and a false pass.
check_idempotent() {
    local sample="$1" name="$2" lens_model="$3"
    shift 3
    local tmp
    tmp=$(prepare_copy "$sample")
    printf 'tmp: %s\n' "$tmp"

    run_glasser --no-confirm "$tmp" >/dev/null || {
        printf '  ✗ glasser failed (run 1)\n' >&2
        return 1
    }
    check_tag "$tmp/$name" LensModel "$lens_model" || return 1
    local before after
    before=$(exiftool -j "$@" "$tmp" 2>/dev/null)
    run_glasser --no-confirm "$tmp" >/dev/null || {
        printf '  ✗ glasser failed (run 2, on the already tagged folder)\n' >&2
        return 1
    }
    after=$(exiftool -j "$@" "$tmp" 2>/dev/null)

    if [[ -z "$before" ]]; then
        printf '  ✗ exiftool did not read the tags\n' >&2
        return 1
    fi
    if [[ "$before" != "$after" ]]; then
        printf '  ✗ key tags changed on retagging:\n' >&2
        diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") >&2
        return 1
    fi
    return 0
}

check_idempotent_fuji() {
    check_idempotent "$SCRIPT_DIR/samples/Fuji + Konica" _DSF1160.JPG \
        "Hexanon AR 57mm F1.4" \
        -LensMake -LensModel -LensSerialNumber -LensInfo \
        -FocalLength -FocalLengthIn35mmFormat -MaxApertureValue \
        -FujiFilm:MinFocalLength -FujiFilm:MaxFocalLength \
        -FujiFilm:MaxApertureAtMinFocal -FujiFilm:MaxApertureAtMaxFocal \
        -XMP-aux:Lens -XMP-aux:LensSerialNumber -XMP-aux:SerialNumber \
        -XMP-exifEX:LensMake -XMP-exifEX:LensModel \
        -XMP-exifEX:LensSerialNumber
}

# The Nikon quantization (58→58.2 mm) is of special interest: the value
# must be stable after the first write.
check_idempotent_nikon() {
    check_idempotent "$SCRIPT_DIR/samples/Nikon + Primoplan" _DSC0020.JPG \
        "Biotar 58mm f/2" \
        -LensMake -LensModel -LensSerialNumber -LensInfo \
        -FocalLength -FocalLengthIn35mmFormat -MaxApertureValue \
        -Nikon:MinFocalLength -Nikon:MaxFocalLength \
        -Nikon:MaxApertureAtMinFocal -Nikon:MaxApertureAtMaxFocal \
        -Nikon:Lens \
        -XMP-aux:Lens -XMP-aux:LensSerialNumber -XMP-aux:SerialNumber \
        -XMP-exifEX:LensMake -XMP-exifEX:LensModel \
        -XMP-exifEX:LensSerialNumber -XMP-exifEX:LensInfo
}

# "Raw" file from the camera: the adapter reports a 50/1.5G profile, the
# lens is really a Primoplan 58. Without a hint detect may find something
# at 50/1.5 in the database, but that is "guessing by the adapter profile",
# not the truth. With an explicit --lens biotar-58 everything is rewritten;
# check that the override works and leaves per-shot FNumber=1.5 alone.
# Optional sample: skipped without it.
check_unedit_nikon_primoplan() {
    local sample="$SCRIPT_DIR/samples/Nikon + Primoplan (unedit)"
    if [[ ! -d "$sample" ]]; then
        printf '  ⤳ no sample: %s\n' "$sample"
        return "$SKIP_RC"
    fi
    local tmp
    tmp=$(prepare_copy "$sample")
    printf 'tmp: %s\n' "$tmp"

    local errs=0

    # Override via --lens biotar-58: correct tagging.
    run_glasser --no-confirm --lens biotar-58 "$tmp" >/dev/null || {
        printf '  ✗ glasser --no-confirm --lens biotar-58 failed\n' >&2
        return 1
    }

    local file="$tmp/_DSC0020.JPG"
    check_tag "$file" LensMake          "Carl Zeiss Jena"               || errs=$((errs+1))
    check_tag "$file" LensModel         "Biotar 58mm f/2"              || errs=$((errs+1))
    check_tag "$file" LensSerialNumber  "4471395"                          || errs=$((errs+1))
    check_tag "$file" LensInfo          "58mm f/2"                        || errs=$((errs+1))
    check_tag "$file" FocalLength       "58.0 mm"                           || errs=$((errs+1))
    check_tag "$file" FocalLengthIn35mmFormat "58 mm"                       || errs=$((errs+1))
    check_tag "$file" MaxApertureValue  "2.0"                               || errs=$((errs+1))
    check_tag "$file" "Nikon:MinFocalLength" "58.2 mm"                      || errs=$((errs+1))
    check_tag "$file" "Nikon:MaxApertureAtMinFocal" "2.0"                   || errs=$((errs+1))
    check_tag "$file" "Nikon:Lens" "58mm f/2"                             || errs=$((errs+1))
    check_tag "$file" "XMP-aux:Lens" "Carl Zeiss Jena Biotar 58mm f/2" || errs=$((errs+1))
    # Per-shot FNumber is untouched: the adapter's original 1.5 must stay.
    check_tag "$file" FNumber           "1.5"                               || errs=$((errs+1))

    return "$errs"
}

# Mixed folder: Fuji+Konica and Nikon+Primoplan together. glasser must
# recognize two groups and tag each with its own tags.
check_mixed_two_groups() {
    local tmp
    tmp=$(new_tmpdir)
    cp "$SCRIPT_DIR/samples/Fuji + Konica/_DSF1160.JPG" "$tmp/fuji.JPG"
    cp "$SCRIPT_DIR/samples/Nikon + Primoplan/_DSC0020.JPG" "$tmp/nikon.JPG"
    printf 'tmp: %s\n' "$tmp"

    run_glasser --no-confirm "$tmp" >/dev/null || {
        printf 'glasser failed on the mixed folder\n' >&2
        return 1
    }

    local errs=0
    # The Fuji file must have the Konica Hexanon data.
    check_tag "$tmp/fuji.JPG" LensMake  "Konica"               || errs=$((errs+1))
    check_tag "$tmp/fuji.JPG" LensModel "Hexanon AR 57mm F1.4" || errs=$((errs+1))
    check_tag "$tmp/fuji.JPG" FocalLength "57.0 mm"            || errs=$((errs+1))
    # The Nikon file must have the biotar-58 data (the only 58 mm in the database).
    check_tag "$tmp/nikon.JPG" LensMake  "Carl Zeiss Jena" || errs=$((errs+1))
    check_tag "$tmp/nikon.JPG" LensModel "Biotar 58mm f/2" || errs=$((errs+1))
    check_tag "$tmp/nikon.JPG" FocalLength "58.0 mm"           || errs=$((errs+1))
    # No cross-contamination: the Fuji file must not get Nikon tags.
    local fuji_nikon_lens
    fuji_nikon_lens=$(exiftool -s -s -s -Nikon:Lens "$tmp/fuji.JPG" 2>/dev/null)
    if [[ -n "$fuji_nikon_lens" ]]; then
        printf '  ✗ Fuji file got Nikon:Lens: %q\n' "$fuji_nikon_lens" >&2
        errs=$((errs+1))
    fi

    return "$errs"
}

# Smoke test for many files in one group: N copies of one sample,
# check the first, middle and last. The `-@ argfile` path is nothing
# special here: every run uses it. Hitting ARG_MAX would take
# ~3000+ files (on macOS); at 12 MB per JPG that is unrealistic.
# Controlled by GLASSER_LOAD_N (default 5, 0 = skip).
check_load_many_files() {
    local count="${GLASSER_LOAD_N:-5}"
    if [[ "$count" == "0" ]]; then
        printf '  ⤳ GLASSER_LOAD_N=0\n'
        return "$SKIP_RC"
    fi

    local sample="$SCRIPT_DIR/samples/Fuji + Konica/_DSF1160.JPG"
    local tmp
    tmp=$(new_tmpdir)
    printf 'tmp: %s, copies: %d\n' "$tmp" "$count"

    local i
    for ((i=1; i<=count; i++)); do
        cp "$sample" "$(printf '%s/copy_%04d.JPG' "$tmp" "$i")"
    done

    run_glasser --no-confirm "$tmp" >/dev/null || {
        printf 'glasser failed on %d copies\n' "$count" >&2
        return 1
    }

    local errs=0
    # Check the first, middle, last: all must get the Konica tags.
    local mid=$(( (count + 1) / 2 ))
    local probe_indexes=(1 "$mid" "$count")
    local idx f
    for idx in "${probe_indexes[@]}"; do
        f=$(printf '%s/copy_%04d.JPG' "$tmp" "$idx")
        check_tag "$f" LensMake  "Konica"               || errs=$((errs+1))
        check_tag "$f" LensModel "Hexanon AR 57mm F1.4" || errs=$((errs+1))
        check_tag "$f" FocalLength "57.0 mm"            || errs=$((errs+1))
    done

    return "$errs"
}

# detect_lens, step 2 (by FocalLength): take the tagged Nikon sample,
# wipe LensMake/LensModel/LensInfo, but keep FocalLength=58.
# detect must find biotar-58 by focal length (not by LensModel).
check_detect_by_focal() {
    local sample="$SCRIPT_DIR/samples/Nikon + Primoplan"
    local tmp
    tmp=$(prepare_copy "$sample")
    printf 'tmp: %s\n' "$tmp"

    # Wipe the lens fields, but NOT FocalLength.
    exiftool -overwrite_original -LensMake= -LensModel= -LensInfo= \
             -LensSerialNumber= \
             -XMP-aux:Lens= -XMP-aux:SerialNumber= -XMP-aux:LensSerialNumber= \
             -XMP-exifEX:LensMake= -XMP-exifEX:LensModel= \
             -XMP-exifEX:LensSerialNumber= -XMP-exifEX:LensInfo= \
             "$tmp/_DSC0020.JPG" "$tmp/_DSC0020.NEF" >/dev/null 2>&1

    # Confirm that LensModel is empty and FocalLength intact.
    local lm fl
    lm=$(exiftool -s -s -s -LensModel "$tmp/_DSC0020.JPG" 2>/dev/null)
    fl=$(exiftool -s -s -s -FocalLength "$tmp/_DSC0020.JPG" 2>/dev/null)
    if [[ -n "$lm" ]]; then
        printf '  ✗ LensModel must be empty, but it is: %q\n' "$lm" >&2
        return 1
    fi
    if [[ "$fl" != "58.0 mm" ]]; then
        printf '  ✗ FocalLength must be 58.0 mm, but it is: %q\n' "$fl" >&2
        return 1
    fi

    # Run glasser without --lens: detect must work via step 2.
    run_glasser --no-confirm "$tmp" >/dev/null || {
        printf '  ✗ glasser could not find the lens by focal length\n' >&2
        return 1
    }

    local errs=0
    local file="$tmp/_DSC0020.JPG"
    check_tag "$file" LensMake "Carl Zeiss Jena"      || errs=$((errs+1))
    check_tag "$file" LensModel "Biotar 58mm f/2"    || errs=$((errs+1))
    check_tag "$file" FocalLength "58.0 mm"               || errs=$((errs+1))

    return "$errs"
}

# Mixed folder with three guessable groups (the third is a Nikon file
# retagged as Hexanon). Dry-run, files untouched; check that glasser
# listed all three groups in the header, the group headings and the plan.
check_mixed_three_groups() {
    local tmp
    tmp=$(new_tmpdir)
    cp "$SCRIPT_DIR/samples/Fuji + Konica/_DSF1160.JPG" "$tmp/group1.JPG"
    cp "$SCRIPT_DIR/samples/Nikon + Primoplan/_DSC0020.JPG" "$tmp/group2.JPG"
    # Third group: another Nikon file, but with a different LensModel.
    cp "$SCRIPT_DIR/samples/Nikon + Primoplan/_DSC0020.JPG" "$tmp/group3.JPG"
    exiftool -overwrite_original -LensModel='Hexanon AR 57mm F1.4' \
             -LensMake='Konica' -FocalLength=57 \
             "$tmp/group3.JPG" >/dev/null 2>&1
    printf 'tmp: %s\n' "$tmp"

    local out
    out=$(run_glasser --dry-run --no-confirm "$tmp" 2>&1) || {
        printf '  ✗ glasser failed on the trio folder\n' >&2
        printf '%s\n' "$out" >&2
        return 1
    }

    local errs=0
    # There must be three group headings.
    local group_headers
    group_headers=$(printf '%s\n' "$out" | grep -c '^\[Group [123]/3\]')
    if [[ "$group_headers" != "3" ]]; then
        printf '  ✗ expected 3 group headings, found: %s\n' "$group_headers" >&2
        errs=$((errs+1))
    fi
    # There must be a line about 3 groups in the header.
    if ! printf '%s\n' "$out" | grep -q 'groups: 3'; then
        printf '  ✗ header does not show "groups: 3"\n' >&2
        errs=$((errs+1))
    fi
    # There must be a "Write plan" with three lines [1] [2] [3].
    local plan_lines
    plan_lines=$(printf '%s\n' "$out" | awk '/━━━ Write plan ━━━/{f=1; next} f && /^  \[/{print}' | wc -l | tr -d ' ')
    if [[ "$plan_lines" != "3" ]]; then
        printf '  ✗ expected 3 lines in the plan, found: %s\n' "$plan_lines" >&2
        errs=$((errs+1))
    fi

    return "$errs"
}

# --dry-run with multiple groups: nothing must be written (file md5s
# unchanged), and the output has two exiftool commands, one per group.
check_dry_run_multi_group() {
    local tmp
    tmp=$(new_tmpdir)
    cp "$SCRIPT_DIR/samples/Fuji + Konica/_DSF1160.JPG" "$tmp/fuji.JPG"
    cp "$SCRIPT_DIR/samples/Nikon + Primoplan/_DSC0020.JPG" "$tmp/nikon.JPG"
    printf 'tmp: %s\n' "$tmp"

    local md5_fuji_before md5_nikon_before
    md5_fuji_before=$(md5 -q "$tmp/fuji.JPG")
    md5_nikon_before=$(md5 -q "$tmp/nikon.JPG")

    local out rc=0
    out=$(run_glasser --dry-run --no-confirm "$tmp" 2>&1) || rc=$?

    local errs=0
    if [[ $rc -ne 0 ]]; then
        printf '  ✗ dry-run exited with rc=%d:\n%s\n' "$rc" "$out" >&2
        errs=$((errs+1))
    fi
    # The files must not change.
    local md5_fuji_after md5_nikon_after
    md5_fuji_after=$(md5 -q "$tmp/fuji.JPG")
    md5_nikon_after=$(md5 -q "$tmp/nikon.JPG")
    if [[ "$md5_fuji_before" != "$md5_fuji_after" ]]; then
        printf '  ✗ fuji.JPG changed under --dry-run\n' >&2
        errs=$((errs+1))
    fi
    if [[ "$md5_nikon_before" != "$md5_nikon_after" ]]; then
        printf '  ✗ nikon.JPG changed under --dry-run\n' >&2
        errs=$((errs+1))
    fi
    # The output has two exiftool command blocks (two "exiftool \" lines).
    local exiftool_calls
    exiftool_calls=$(printf '%s\n' "$out" | grep -c '^exiftool \\$')
    if [[ "$exiftool_calls" != "2" ]]; then
        printf '  ✗ expected 2 exiftool calls in dry-run, found: %s\n' "$exiftool_calls" >&2
        errs=$((errs+1))
    fi
    # There must be no "✓ Done." line (nothing was written).
    if printf '%s\n' "$out" | grep -q '✓ Done'; then
        printf '  ✗ final summary appeared in dry-run\n' >&2
        errs=$((errs+1))
    fi

    return "$errs"
}

# Retagging with a lens without a serial: the previous lens serial must
# be cleared, the body serial kept. The sample is already tagged with a
# lens with a serial, including an old XMP-aux:SerialNumber = lens serial.
check_retag_clears_serial() {
    local sample="$SCRIPT_DIR/samples/Nikon + Primoplan"
    local tmp
    tmp=$(prepare_copy "$sample")
    printf 'tmp: %s\n' "$tmp"
    # The body serial comes from the sample, not hard-coded.
    local body
    body=$(exiftool -s3 -ExifIFD:SerialNumber "$tmp/_DSC0020.JPG")
    [[ -n "$body" ]] || { printf '  ✗ no body serial in the sample\n' >&2; return 1; }

    run_glasser --no-confirm --lens jupiter-9 "$tmp" >/dev/null || {
        printf 'glasser failed\n' >&2
        return 1
    }

    local errs=0 file
    for file in "$tmp/_DSC0020.JPG" "$tmp/_DSC0020.NEF"; do
        check_tag "$file" LensModel                     "9 85mm f/2" || errs=$((errs+1))
        check_tag "$file" "ExifIFD:LensSerialNumber"    ""               || errs=$((errs+1))
        check_tag "$file" "XMP-exifEX:LensSerialNumber" ""               || errs=$((errs+1))
        check_tag "$file" "XMP-aux:LensSerialNumber"    ""               || errs=$((errs+1))
        check_tag "$file" "XMP-aux:SerialNumber"        ""               || errs=$((errs+1))
        check_tag "$file" "ExifIFD:SerialNumber"        "$body"          || errs=$((errs+1))
    done

    return "$errs"
}

# XMP-aux:SerialNumber written not by glasser (equal to the body serial)
# must not be cleared: only the old lens serial is cleaned up.
check_keeps_body_serial_in_aux() {
    local sample="$SCRIPT_DIR/samples/Nikon + Primoplan"
    local tmp
    tmp=$(prepare_copy "$sample")
    printf 'tmp: %s\n' "$tmp"
    local file="$tmp/_DSC0020.JPG" body
    body=$(exiftool -s3 -ExifIFD:SerialNumber "$file")
    [[ -n "$body" ]] || { printf '  ✗ no body serial in the sample\n' >&2; return 1; }

    exiftool -overwrite_original -XMP-aux:SerialNumber="$body" \
             "$file" >/dev/null 2>&1

    run_glasser --no-confirm --lens biotar-58 "$tmp" >/dev/null || {
        printf 'glasser failed\n' >&2
        return 1
    }

    local errs=0
    check_tag "$file" "XMP-aux:SerialNumber"     "$body"    || errs=$((errs+1))
    check_tag "$file" "XMP-aux:LensSerialNumber" "4471395" || errs=$((errs+1))

    return "$errs"
}

# An unknown MakerNote group in add_camera must fail the run at once,
# not give a plan "MakerNote (X) = …" without matching tags in the command.
check_unknown_makernote_group() {
    local tmp
    tmp=$(new_tmpdir)
    printf 'tmp: %s\n' "$tmp"
    # A copy of the script with an extra camera; glasser itself is untouched.
    awk '{ print }
         /^    add_camera "fuji-xe3"/ {
             print "    add_camera \"sony-a7\" \"^SONY\" \"^ILCE-7$\" \"Sony A7\" \"1.0\" \"Sony\" \"false\""
         }' "$GLASSER" > "$tmp/glasser"
    chmod +x "$tmp/glasser"

    local out rc=0
    out=$("$BASH_BIN" "$tmp/glasser" --list-cameras 2>&1) || rc=$?

    local errs=0
    if [[ $rc -eq 0 ]]; then
        printf '  ✗ expected an error on the Sony MakerNote group, rc=0\n' >&2
        errs=$((errs+1))
    fi
    if ! printf '%s\n' "$out" | grep -q 'unknown MakerNote group'; then
        printf '  ✗ no message about the unknown MakerNote group:\n%s\n' "$out" >&2
        errs=$((errs+1))
    fi

    return "$errs"
}

# File without LensModel (the adapter passed only focal length and aperture):
# the "EXIF:" line must show FocalLength/MaxAperture in their places, not
# shifted left (TAB splitting collapsed the empty field).
check_exif_line_empty_lensmodel() {
    local tmp
    tmp=$(new_tmpdir)
    cp "$SCRIPT_DIR/samples/Nikon + Primoplan/_DSC0020.JPG" "$tmp/a.JPG"
    exiftool -q -overwrite_original -LensModel= -Lens= -LensInfo= -LensMake= \
             -FocalLength=58 -MaxApertureValue=1.9 "$tmp/a.JPG" >/dev/null 2>&1
    printf 'tmp: %s\n' "$tmp"

    local out errs=0
    out=$(run_glasser --dry-run --no-confirm "$tmp" 2>&1)
    local line
    line=$(printf '%s\n' "$out" | grep '^EXIF:')
    case "$line" in
        *"FocalLength=58mm"*"MaxAperture=f/1.9"*) ;;
        *) printf '  ✗ EXIF line: %s\n' "$line" >&2; errs=$((errs+1)) ;;
    esac
    case "$line" in
        *LensModel=*) printf '  ✗ stray LensModel in: %s\n' "$line" >&2; errs=$((errs+1)) ;;
    esac

    return "$errs"
}

# Ambiguous guess: 50/1.2 fits both canon-fd-50-12 and canon-fd-50-12l;
# --no-confirm must fail with the list of candidates, not take the first
# database row. With --lens it works. 50/1.9 is unique in the database: guessed.
check_ambiguous_lens() {
    local tmp
    tmp=$(new_tmpdir)
    cp "$SCRIPT_DIR/samples/Nikon + Primoplan/_DSC0020.JPG" "$tmp/a.JPG"
    exiftool -q -overwrite_original -LensModel= -Lens= -LensInfo= -LensMake= \
             -FocalLength=50 -MaxApertureValue=1.2 "$tmp/a.JPG" >/dev/null 2>&1
    printf 'tmp: %s\n' "$tmp"

    local out rc errs=0
    rc=0; out=$(run_glasser --dry-run --no-confirm "$tmp" 2>&1) || rc=$?
    if [[ $rc -eq 0 ]]; then
        printf '  ✗ 50/1.2 without --lens: expected an error, rc=0\n' >&2
        errs=$((errs+1))
    fi
    if ! printf '%s\n' "$out" | grep -q 'lens is ambiguous: canon-fd-50-12, canon-fd-50-12l'; then
        printf '  ✗ no candidate list:\n%s\n' "$out" >&2
        errs=$((errs+1))
    fi
    rc=0; run_glasser --dry-run --no-confirm --lens canon-fd-50-12l "$tmp" >/dev/null 2>&1 || rc=$?
    if [[ $rc -ne 0 ]]; then
        printf '  ✗ 50/1.2 with --lens canon-fd-50-12l: rc=%d\n' "$rc" >&2
        errs=$((errs+1))
    fi

    # The same LensModel without LensMake matches two database rows (step 1).
    exiftool -q -overwrite_original -LensModel='FD 50mm f/1.2 L' "$tmp/a.JPG" >/dev/null 2>&1
    rc=0; out=$(run_glasser --dry-run --no-confirm "$tmp" 2>&1) || rc=$?
    if [[ $rc -eq 0 ]] || ! printf '%s\n' "$out" | grep -q 'lens is ambiguous'; then
        printf '  ✗ LensModel "FD 50mm f/1.2 L" without LensMake: expected ambiguity, rc=%d\n' "$rc" >&2
        errs=$((errs+1))
    fi

    exiftool -q -overwrite_original -LensModel= -MaxApertureValue=1.9 "$tmp/a.JPG" >/dev/null 2>&1
    rc=0; out=$(run_glasser --dry-run --no-confirm "$tmp" 2>&1) || rc=$?
    if [[ $rc -ne 0 ]] || ! printf '%s\n' "$out" | grep -q 'Xenon 50mm f/1\.9.*← guessed'; then
        printf '  ✗ 50/1.9 must be guessed as xenon-50, rc=%d\n' "$rc" >&2
        errs=$((errs+1))
    fi

    # Focal length not in the database, MaxApertureValue set: zero candidates
    # must not crash bash 3.2 (empty array under set -u); just the usual
    # "lens not guessed".
    exiftool -q -overwrite_original -FocalLength=23 -MaxApertureValue=2 \
             "$tmp/a.JPG" >/dev/null 2>&1
    rc=0; out=$(run_glasser --dry-run --no-confirm "$tmp" 2>&1) || rc=$?
    if [[ $rc -ne 1 ]] || ! printf '%s\n' "$out" | grep -q 'lens not guessed' \
       || printf '%s\n' "$out" | grep -q 'unbound variable'; then
        printf '  ✗ 23/2 (not in the database): expected rc=1 and "lens not guessed", rc=%d:\n%s\n' \
               "$rc" "$out" >&2
        errs=$((errs+1))
    fi

    return "$errs"
}

# Fallback to LensInfo when MaxApertureValue is empty: among the 50 mm
# lenses of the database f/1.9 and f/2 are unique (xenon-50, nikkor-h-50);
# only LensInfo gives the aperture for the tie-break. "50 50 1.9 1.9" → Xenon,
# "50 50 2 2" → Nikkor-H.
check_lensinfo_fallback() {
    local tmp
    tmp=$(new_tmpdir)
    cp "$SCRIPT_DIR/samples/Nikon + Primoplan/_DSC0020.JPG" "$tmp/a.JPG"
    exiftool -q -overwrite_original -LensMake= -LensModel= -Lens= \
             -XMP-aux:Lens= -XMP-exifEX:LensMake= -XMP-exifEX:LensModel= \
             -XMP-exifEX:LensInfo= -MaxApertureValue= -FocalLength=50 \
             -LensInfo='50 50 1.9 1.9' "$tmp/a.JPG" >/dev/null 2>&1
    printf 'tmp: %s\n' "$tmp"

    local out rc errs=0
    rc=0; out=$(run_glasser --dry-run --no-confirm "$tmp" 2>&1) || rc=$?
    if [[ $rc -ne 0 ]] || ! printf '%s\n' "$out" | grep -q 'Xenon 50mm f/1\.9.*← guessed'; then
        printf '  ✗ LensInfo 50/1.9: expected xenon-50, rc=%d:\n%s\n' "$rc" "$out" >&2
        errs=$((errs+1))
    fi

    exiftool -q -overwrite_original -LensInfo='50 50 2 2' "$tmp/a.JPG" >/dev/null 2>&1
    rc=0; out=$(run_glasser --dry-run --no-confirm "$tmp" 2>&1) || rc=$?
    if [[ $rc -ne 0 ]] || ! printf '%s\n' "$out" | grep -q 'Nikkor-H Auto 50mm f/2.*← guessed'; then
        printf '  ✗ LensInfo 50/2: expected nikkor-h-50, rc=%d:\n%s\n' "$rc" "$out" >&2
        errs=$((errs+1))
    fi

    return "$errs"
}

# Atomic commit phase: in --no-confirm group 1 is guessed, group 2 is not
# (focal length 13 mm, not in the database). rc=1, and no file changed:
# nothing is written before the plan is applied.
check_no_confirm_atomic() {
    local tmp
    tmp=$(new_tmpdir)
    cp "$SCRIPT_DIR/samples/Nikon + Primoplan/_DSC0020.JPG" "$tmp/nikon.JPG"
    cp "$SCRIPT_DIR/samples/Fuji + Konica/_DSF1160.JPG" "$tmp/fuji.JPG"
    exiftool -q -overwrite_original -LensMake= -LensModel= -Lens= -LensInfo= \
             -XMP-aux:Lens= -XMP-exifEX:LensMake= -XMP-exifEX:LensModel= \
             -XMP-exifEX:LensInfo= -MaxApertureValue= -FocalLength=13 \
             "$tmp/fuji.JPG" >/dev/null 2>&1
    printf 'tmp: %s\n' "$tmp"

    local md5_before md5_after
    md5_before=$(md5 -q "$tmp/nikon.JPG" "$tmp/fuji.JPG")

    local out rc=0 errs=0
    out=$(run_glasser --no-confirm "$tmp" 2>&1) || rc=$?
    md5_after=$(md5 -q "$tmp/nikon.JPG" "$tmp/fuji.JPG")
    if [[ $rc -ne 1 ]]; then
        printf '  ✗ expected rc=1, got %d\n' "$rc" >&2
        errs=$((errs+1))
    fi
    # Group 1 must be accepted, otherwise the test does not check atomicity.
    if ! printf '%s\n' "$out" | grep -q '^✓ Group 1/2'; then
        printf '  ✗ group 1 not accepted:\n%s\n' "$out" >&2
        errs=$((errs+1))
    fi
    if ! printf '%s\n' "$out" | grep -q 'group 2/2: lens not guessed'; then
        printf '  ✗ no error about group 2:\n%s\n' "$out" >&2
        errs=$((errs+1))
    fi
    if [[ "$md5_before" != "$md5_after" ]]; then
        printf '  ✗ files changed although the plan was not applied\n' >&2
        errs=$((errs+1))
    fi

    return "$errs"
}

# A folder whose name starts with '#', passed as a relative path:
# in the -@ argfile such a line would be a comment. Writing must succeed.
check_hash_folder() {
    local tmp
    tmp=$(new_tmpdir)
    mkdir "$tmp/#roll"
    cp "$SCRIPT_DIR/samples/Nikon + Primoplan/_DSC0020.JPG" "$tmp/#roll/a.JPG"
    printf 'tmp: %s\n' "$tmp"

    local errs=0
    (cd "$tmp" && run_glasser --no-confirm --lens jupiter-9 '#roll' >/dev/null) || {
        printf '  ✗ glasser failed on folder #roll\n' >&2
        errs=$((errs+1))
    }
    check_tag "$tmp/#roll/a.JPG" LensModel "9 85mm f/2" || errs=$((errs+1))

    return "$errs"
}

# A file name with a newline and an option line ("-all=") must not
# get into the -@ argfile: a neighbor file without camera EXIF keeps its metadata.
check_newline_filename() {
    local tmp
    tmp=$(new_tmpdir)
    cp "$SCRIPT_DIR/samples/Fuji + Konica/_DSF1160.JPG" "$tmp/nomake.jpg"
    exiftool -q -overwrite_original -all= -DateTimeOriginal='2020:01:01 00:00:00' \
             "$tmp/nomake.jpg" >/dev/null 2>&1
    cp "$tmp/nomake.jpg" "$tmp/evil"$'\n'"-all="$'\n'"x.jpg"
    printf 'tmp: %s\n' "$tmp"

    local out errs=0
    out=$(run_glasser --no-confirm --camera fuji-xt4 --lens hexanon-57-14 "$tmp" 2>&1) || {
        printf '  ✗ glasser failed:\n%s\n' "$out" >&2
        errs=$((errs+1))
    }
    check_tag "$tmp/nomake.jpg" DateTimeOriginal "2020:01:01 00:00:00" || errs=$((errs+1))
    check_tag "$tmp/nomake.jpg" LensModel "Hexanon AR 57mm F1.4"       || errs=$((errs+1))
    if ! printf '%s\n' "$out" | grep -q '1 file skipped'; then
        printf '  ✗ no warning about the skipped file\n' >&2
        errs=$((errs+1))
    fi

    return "$errs"
}

# An exiftool error in one group (a locked file) does not stop the
# others: the second group is tagged, the summary printed, rc != 0.
check_failed_group_continues() {
    local tmp
    tmp=$(new_tmpdir)
    cp "$SCRIPT_DIR/samples/Fuji + Konica/_DSF1160.JPG" "$tmp/fuji.JPG"
    mkdir "$tmp/ro"
    cp "$SCRIPT_DIR/samples/Nikon + Primoplan/_DSC0020.JPG" "$tmp/ro/nikon.JPG"
    # Clear LensModel so that check_tag below proves the Fuji group
    # really was tagged. The group number depends on the file order
    # (exiftool uses readdir order), so groups in the summary are found by
    # content, not by number.
    exiftool -q -overwrite_original -LensModel= -LensMake= "$tmp/fuji.JPG" >/dev/null 2>&1
    # A read-only folder: exiftool cannot create its temporary file next
    # to nikon.JPG, so the Nikon group fails (as root this would not work).
    chmod a-w "$tmp/ro"
    printf 'tmp: %s\n' "$tmp"

    local out rc=0 errs=0
    out=$(run_glasser --no-confirm "$tmp" 2>&1) || rc=$?
    chmod u+w "$tmp/ro"
    if [[ $rc -eq 0 ]]; then
        printf '  ✗ expected rc != 0 on an exiftool error\n' >&2
        errs=$((errs+1))
    fi
    check_tag "$tmp/fuji.JPG" LensModel "Hexanon AR 57mm F1.4" || errs=$((errs+1))
    if ! printf '%s\n' "$out" | grep -q 'Done with errors'; then
        printf '  ✗ no final summary with errors:\n%s\n' "$out" >&2
        errs=$((errs+1))
    fi
    if ! printf '%s\n' "$out" | grep -q '^  \[[0-9]*\]  failed .*Nikon'; then
        printf '  ✗ Nikon group not marked as failed\n' >&2
        errs=$((errs+1))
    fi
    if ! printf '%s\n' "$out" | grep -q '^  \[[0-9]*\]  tagged .*Fujifilm'; then
        printf '  ✗ Fuji group not marked as tagged\n' >&2
        errs=$((errs+1))
    fi

    return "$errs"
}

# Every UI key in glasser (a literal in single quotes after _t, _tv,
# tprintf, errf, dief) has a translation in locale/ru.sh, and the catalog
# has no keys glasser no longer uses.
check_l10n_catalog() {
    local catalog="$SCRIPT_DIR/locale/ru.sh" keys cat_keys
    keys=$(grep -oE "(^|[^A-Za-z_])(_t|tprintf|errf|dief) '[^']*'|_tv [A-Za-z_]+ '[^']*'" "$GLASSER" |
           sed -E "s/^[^']*'//; s/'$//" | sort -u)
    cat_keys=$(sed -nE "s/^        '(.*)'\)$/\1/p" "$catalog" | sort -u)
    if [[ -z "$keys" || -z "$cat_keys" ]]; then
        printf '  ✗ no keys found (glasser: %d, catalog: %d)\n' \
               "$(printf '%s' "$keys" | grep -c .)" "$(printf '%s' "$cat_keys" | grep -c .)" >&2
        return 1
    fi
    if [[ "$keys" != "$cat_keys" ]]; then
        printf '  ✗ glasser keys (<) vs locale/ru.sh (>):\n' >&2
        diff <(printf '%s\n' "$keys") <(printf '%s\n' "$cat_keys") >&2
        return 1
    fi
    return 0
}

# Russian UI: GLASSER_LANG=ru and a ru_* locale select it, GLASSER_LANG
# overrides the locale, a language without a catalog falls back to
# English. Plurals and translated column headers in a dry run.
check_l10n_ru() {
    local tmp out errs=0
    tmp=$(new_tmpdir)
    mkdir "$tmp/d"
    cp "$SCRIPT_DIR/samples/Fuji + Konica/_DSF1160.JPG" "$tmp/d/a.JPG"
    cp "$SCRIPT_DIR/samples/Fuji + Konica/_DSF1160.JPG" "$tmp/d/b.JPG"
    printf 'tmp: %s\n' "$tmp"

    GLASSER_LANG=ru expect_cli 1 'ошибка: неизвестная опция: --bogus' --bogus || errs=$((errs+1))
    GLASSER_LANG='' LC_ALL='' LC_MESSAGES='' LANG=ru_RU.UTF-8 \
        expect_cli 0 'Использование:' --help || errs=$((errs+1))
    GLASSER_LANG=en LANG=ru_RU.UTF-8 expect_cli 0 'Usage:' --help || errs=$((errs+1))
    GLASSER_LANG=de expect_cli 1 'error: unknown option: --bogus' --bogus || errs=$((errs+1))

    out=$(GLASSER_LANG=ru run_glasser --dry-run --no-confirm "$tmp/d" 2>&1) || {
        printf '  ✗ dry-run failed:\n%s\n' "$out" >&2
        return 1
    }
    local want
    for want in 'Всего файлов: 2' '(2 файла)' '━━━ План записи ━━━' \
                '№    Файлов  Камера         Объектив' 'Эквивалент 35мм   = 86 мм'; do
        if ! printf '%s\n' "$out" | grep -qF -- "$want"; then
            printf '  ✗ no "%s" in the Russian dry run:\n%s\n' "$want" "$out" >&2
            errs=$((errs+1))
        fi
    done
    return "$errs"
}

# One row of the check_cli table: runs glasser with arguments $3…,
# compares the return code ($1) and a substring of stdout+stderr ($2; empty
# means don't check). Prints ✗ and returns 1 on mismatch.
expect_cli() {
    local want_rc="$1" want_out="$2"
    shift 2
    local out rc=0
    out=$(run_glasser "$@" 2>&1) || rc=$?
    if [[ $rc -ne $want_rc ]]; then
        printf '  ✗ glasser %s: expected rc=%d, got %d:\n%s\n' "$*" "$want_rc" "$rc" "$out" >&2
        return 1
    fi
    if [[ -n "$want_out" ]] && ! printf '%s\n' "$out" | grep -qF -- "$want_out"; then
        printf '  ✗ glasser %s: no "%s" in the output:\n%s\n' "$*" "$want_out" "$out" >&2
        return 1
    fi
    return 0
}

# Argument parsing and early errors: help/lists give rc 0; bad
# options, id without a value, not a folder, empty folder, extra positional
# argument give rc 1 with a message. "--" does not override a folder already
# given; a bad --lens/--camera is an id error even before scanning (even
# of an empty folder). A folder where all files are filtered out (TAB in the
# path) is an error with the reason and the skipped count, not "no images".
check_cli() {
    local tmp
    tmp=$(new_tmpdir)
    mkdir "$tmp/d3" "$tmp/d4" "$tmp/empty" "$tmp/tab"$'\t'"dir"
    cp "$SCRIPT_DIR/samples/Fuji + Konica/_DSF1160.JPG" "$tmp/tab"$'\t'"dir/a.JPG"
    : > "$tmp/file.txt"
    printf 'tmp: %s\n' "$tmp"

    local errs=0
    expect_cli 0 'glasser --help'  --help                                || errs=$((errs+1))
    expect_cli 0 'glasser 0.1.0'   --version                             || errs=$((errs+1))
    expect_cli 0 'biotar-58'    --list-lenses                         || errs=$((errs+1))
    expect_cli 0 'nikon-zf'        --list-cameras                        || errs=$((errs+1))
    expect_cli 1 'unknown option: --bogus' --bogus                    || errs=$((errs+1))
    expect_cli 1 '--camera requires an ID' --no-confirm --camera             || errs=$((errs+1))
    expect_cli 1 '--lens requires an ID'   --no-confirm --lens               || errs=$((errs+1))
    expect_cli 1 'not a folder'    --no-confirm "$tmp/nonexistent"           || errs=$((errs+1))
    expect_cli 1 'not a folder'    --no-confirm "$tmp/file.txt"              || errs=$((errs+1))
    expect_cli 1 'no images in the folder' --no-confirm "$tmp/empty"     || errs=$((errs+1))
    expect_cli 1 'no readable images in the folder: 1 file skipped — control characters' \
        --no-confirm "$tmp/tab"$'\t'"dir"                                 || errs=$((errs+1))
    expect_cli 1 'extra argument' --no-confirm "$tmp/d3" "$tmp/d4"      || errs=$((errs+1))
    expect_cli 1 'extra argument' --dry-run --no-confirm "$tmp/d3" -- "$tmp/d4" || errs=$((errs+1))
    expect_cli 1 'lens not in the database: bogus' \
        --no-confirm --lens bogus "$tmp/empty"                           || errs=$((errs+1))
    expect_cli 1 'camera not in the database: bogus' \
        --no-confirm --camera bogus "$tmp/empty"                         || errs=$((errs+1))

    return "$errs"
}

# Tables align by characters only with a UTF-8 LC_CTYPE; without it
# glasser switches to a UTF-8 locale itself: output under LC_ALL=C is the same.
check_locale_c() {
    local utf8 c errs=0
    utf8=$(LC_ALL=en_US.UTF-8 run_glasser --list-cameras 2>&1)
    c=$(LC_ALL=C run_glasser --list-cameras 2>&1)
    if [[ -z "$utf8" || "$utf8" != "$c" ]]; then
        printf '  ✗ --list-cameras differs under LC_ALL=C:\n' >&2
        diff <(printf '%s\n' "$utf8") <(printf '%s\n' "$c") >&2
        errs=1
    fi
    return "$errs"
}

# A run without a controlling terminal and without --no-confirm (cron, CI)
# is an error (rc != 0), not "Cancelled" with code 0. setsid via perl: macOS
# has no setsid(1), but always has perl (exiftool runs on it).
check_no_tty() {
    local tmp
    tmp=$(new_tmpdir)
    cp "$SCRIPT_DIR/samples/Nikon + Primoplan/_DSC0020.JPG" "$tmp/a.JPG"
    printf 'tmp: %s\n' "$tmp"
    local md5_before md5_after
    md5_before=$(md5 -q "$tmp/a.JPG")

    local out rc=0 errs=0
    # shellcheck disable=SC2016  # Perl code, not shell
    out=$(perl -MPOSIX -e 'if (my $p = fork) { waitpid($p, 0); exit($? >> 8) }
                           POSIX::setsid(); exec @ARGV or exit 127' \
               "$BASH_BIN" "$GLASSER" "$tmp" </dev/null 2>&1) || rc=$?
    md5_after=$(md5 -q "$tmp/a.JPG")
    if [[ $rc -eq 0 ]]; then
        printf '  ✗ expected rc != 0 without a terminal:\n%s\n' "$out" >&2
        errs=$((errs+1))
    fi
    if ! printf '%s\n' "$out" | grep -q 'no terminal'; then
        printf '  ✗ no "no terminal" message:\n%s\n' "$out" >&2
        errs=$((errs+1))
    fi
    if [[ "$md5_before" != "$md5_after" ]]; then
        printf '  ✗ file changed\n' >&2
        errs=$((errs+1))
    fi

    return "$errs"
}

# Interactive tests run glasser in a pty via expect (part of macOS).
# Without expect: skipped.
need_expect() {
    if ! command -v expect >/dev/null 2>&1; then
        printf '  ⤳ no expect\n'
        return 1
    fi
    return 0
}

# Expect scenario for interactive tests: argv = bash, glasser, folder,
# file for stdout (stdout is not a TTY → no cards and no CPR queries), then
# "expected text / answer" pairs (answer "-" means just wait for the text,
# "^D" sends EOF). Timeout or early EOF gives code 99/98, otherwise glasser's
# exit code. Expected text is ASCII only: expect shifts the match boundary
# on multibyte UTF-8 and eats the start of the following output.
write_expect_script() {
    cat > "$1" <<'EOF'
set timeout 30
set b [lindex $argv 0]
set g [lindex $argv 1]
set d [lindex $argv 2]
set out [lindex $argv 3]
spawn /bin/sh -c "exec \"$b\" \"$g\" \"$d\" > \"$out\""
foreach {pat ans} [lrange $argv 4 end] {
    expect {
        timeout { puts stderr "timeout: $pat"; exit 99 }
        eof     { puts stderr "eof: $pat"; exit 98 }
        -ex $pat {
            if {$ans eq "^D"} {
                send -- "\004"
            } elseif {$ans ne "-"} {
                send -- "$ans\r"
            }
        }
    }
}
expect eof
catch wait result
exit [lindex $result 3]
EOF
}

# Prepares folder $1/d with two groups (nikon.JPG is group 1, fuji.JPG is
# group 2) and the expect script $1/run.exp.
prepare_interactive() {
    mkdir "$1/d"
    cp "$SCRIPT_DIR/samples/Fuji + Konica/_DSF1160.JPG" "$1/d/fuji.JPG"
    cp "$SCRIPT_DIR/samples/Nikon + Primoplan/_DSC0020.JPG" "$1/d/nikon.JPG"
    write_expect_script "$1/run.exp"
}

# Number of the lens with ID $1 in the lens menu (menu order is database
# order, as in --list-lenses). Tests pick an item by ID, not by a hard-coded
# number: new database rows shift the numbers.
lens_menu_pos() {
    run_glasser --list-lenses | awk -v id="$1" 'NR > 1 && $1 == id { print NR - 1; exit }'
}

# Same for the camera menu (--list-cameras order).
camera_menu_pos() {
    run_glasser --list-cameras | awk -v id="$1" 'NR > 1 && $1 == id { print NR - 1; exit }'
}

# Number of camera menu items (without "0)"): --list-cameras rows minus the header.
camera_menu_count() {
    run_glasser --list-cameras | awk 'NR > 1 && NF { n++ } END { print n + 0 }'
}

# Runs the expect scenario from $1 (folder from prepare_interactive) with
# answers $2…; glasser stdout goes to $1/out.txt, the pty log to $1/exp.log.
# Returns glasser's exit code (or 98/99 from expect).
run_interactive() {
    local tmp="$1"
    shift
    expect "$tmp/run.exp" "$BASH_BIN" "$GLASSER" "$tmp/d" "$tmp/out.txt" "$@" \
        >"$tmp/exp.log" 2>&1
}

# "s" at "Accept?" skips the group: its file is untouched, the second
# group is tagged, the summary says "skipped".
check_interactive_skip() {
    need_expect || return "$SKIP_RC"
    local tmp
    tmp=$(new_tmpdir)
    prepare_interactive "$tmp"
    printf 'tmp: %s\n' "$tmp"
    local md5_nikon
    md5_nikon=$(md5 -q "$tmp/d/nikon.JPG")

    local errs=0 rc=0
    run_interactive "$tmp" '> ' s  '> ' y  'Y/n' y || rc=$?
    expect_rc0 "$rc" "$tmp/exp.log" || errs=$((errs+1))
    if ! grep -q '^⤳ Group 1/2: skipped' "$tmp/out.txt"; then
        printf '  ✗ group 1 not marked skipped:\n' >&2
        cat "$tmp/out.txt" >&2
        errs=$((errs+1))
    fi
    if [[ "$(md5 -q "$tmp/d/nikon.JPG")" != "$md5_nikon" ]]; then
        printf '  ✗ file of the skipped group changed\n' >&2
        errs=$((errs+1))
    fi
    check_tag "$tmp/d/fuji.JPG" LensModel "Hexanon AR 57mm F1.4" || errs=$((errs+1))
    if ! grep -q 'Total: 1 file tagged, 1 file skipped' "$tmp/out.txt"; then
        printf '  ✗ no total "1 tagged, 1 skipped"\n' >&2
        errs=$((errs+1))
    fi

    return "$errs"
}

# Cancel: "n" at "Apply the plan?" and "q" at "Accept?" give rc 0,
# "Cancelled. Nothing written.", files unchanged. Ctrl-D in the middle of
# the interactive part gives rc 1, "input closed", files unchanged.
check_interactive_cancel() {
    need_expect || return "$SKIP_RC"
    local tmp
    tmp=$(new_tmpdir)
    prepare_interactive "$tmp"
    printf 'tmp: %s\n' "$tmp"
    local md5_before
    md5_before=$(md5 -q "$tmp/d/nikon.JPG" "$tmp/d/fuji.JPG")

    local errs=0 rc label
    # Expect answers per scenario ("text / answer" pairs).
    local -a cases_n=('> ' y '> ' y 'Y/n' n)
    local -a cases_q=('> ' q)
    local -a cases_eof=('> ' y '> ' '^D')
    for label in n q eof; do
        rc=0
        case "$label" in
            n)   run_interactive "$tmp" "${cases_n[@]}"   || rc=$? ;;
            q)   run_interactive "$tmp" "${cases_q[@]}"   || rc=$? ;;
            eof) run_interactive "$tmp" "${cases_eof[@]}" || rc=$? ;;
        esac
        if [[ $label == eof ]]; then
            if [[ $rc -ne 1 ]] || ! grep -q 'input closed (EOF, Ctrl-D) — nothing written' "$tmp/exp.log"; then
                printf '  ✗ Ctrl-D: expected rc=1 and "input closed", rc=%d\n' "$rc" >&2
                tail -5 "$tmp/exp.log" >&2
                errs=$((errs+1))
            fi
        else
            if [[ $rc -ne 0 ]] || ! grep -q '^Cancelled. Nothing written.' "$tmp/out.txt"; then
                printf '  ✗ "%s": expected rc=0 and "Cancelled", rc=%d\n' "$label" "$rc" >&2
                tail -5 "$tmp/out.txt" >&2
                errs=$((errs+1))
            fi
        fi
        if [[ "$(md5 -q "$tmp/d/nikon.JPG" "$tmp/d/fuji.JPG")" != "$md5_before" ]]; then
            printf '  ✗ "%s": files changed\n' "$label" >&2
            errs=$((errs+1))
        fi
    done

    return "$errs"
}

# Expect scenario for card mode: glasser's stdin, stdout and stderr are a pty
# of fixed size, TERM is normal, and the scenario itself is a small
# terminal emulator. It keeps a screen (rows × cols, wrap at the edge,
# scrolling into scroll-back), understands what glasser sends (CR/LF, CSI
# A/B/C/D/G/H/J/K, ESC 7/8), and answers CSI 6n with the real cursor
# position, so the screen itself can be checked, not the byte stream. This is
# a terminal model, not a copy of Terminal.app: e.g. it does not push ED from
# home and ED 2 into scroll-back (tmux and other terminals do); the behavior
# of a real terminal is checked by the tmux tests (check_tmux_cards*).
# argv = rows, cols, whether to answer CSI 6n (1/0), screen file prefix,
# number of command words, the command words, then "expected text /
# answer" pairs. The text is compared with the end of the screen line left of
# the cursor (that is, the prompt the cursor sits at), ASCII only. The answer
# is sent with Enter; after an answer the next prompt is looked for only
# after a newline (the answer's echo).
# Files: <prefix>.N is the screen at the N-th answer, <prefix> the screen at
# the end, <prefix>.full scroll-back + screen, <prefix>.stats the number of
# CSI 6n, ms from the first CSI 6n to the next visible character and how many
# answers were given. Exit code as glasser's (130 = killed by SIGINT),
# timeout gives 99.
write_vt_expect_script() {
    cat > "$1" <<'EOF'
set timeout 30
encoding system utf-8
set env(TERM) xterm-256color
set rows [lindex $argv 0]
set cols [lindex $argv 1]
set cpr [lindex $argv 2]
set out [lindex $argv 3]
set n [lindex $argv 4]
set cmd [lrange $argv 5 [expr {4 + $n}]]
set pairs [lrange $argv [expr {5 + $n}] end]

set scr {}
for {set i 0} {$i < $rows} {incr i} { lappend scr "" }
set sb {}
set row 0
set col 0
set srow 0
set scol 0
set st norm
set par ""
set armed 1
set pi 0
set queries 0
set t_query 0
set cpr_wait -1

proc lf {} {
    global row rows scr sb
    if {$row == $rows - 1} {
        lappend sb [lindex $scr 0]
        set scr [lrange $scr 1 end]
        lappend scr ""
    } else {
        incr row
    }
}

proc putc {ch} {
    global row col cols scr
    if {$col >= $cols} { set col 0; lf }
    set line [lindex $scr $row]
    set len [string length $line]
    if {$len < $col} { append line [string repeat " " [expr {$col - $len}]] }
    set line "[string range $line 0 [expr {$col - 1}]]$ch[string range $line [expr {$col + 1}] end]"
    lset scr $row $line
    incr col
}

proc csi {p f} {
    global row col rows cols scr cpr queries t_query
    if {[string index $p 0] eq "?"} { return }
    set a [split $p ";"]
    set n [lindex $a 0]
    if {$n eq "" || $n == 0} { set n1 1 } else { set n1 $n }
    switch -- $f {
        A { set row [expr {max(0, $row - $n1)}] }
        B { set row [expr {min($rows - 1, $row + $n1)}] }
        C { set col [expr {min($cols - 1, $col + $n1)}] }
        D { set col [expr {max(0, $col - $n1)}] }
        G { set col [expr {$n1 - 1}] }
        H - f {
            set r [lindex $a 0]
            set c [lindex $a 1]
            if {$r eq ""} { set r 1 }
            if {$c eq ""} { set c 1 }
            set row [expr {$r - 1}]
            set col [expr {$c - 1}]
        }
        J {
            if {$n eq "" || $n == 0} {
                lset scr $row [string range [lindex $scr $row] 0 [expr {$col - 1}]]
                for {set i [expr {$row + 1}]} {$i < $rows} {incr i} { lset scr $i "" }
            } elseif {$n == 2 || $n == 3} {
                for {set i 0} {$i < $rows} {incr i} { lset scr $i "" }
            }
        }
        K {
            if {$n eq "" || $n == 0} {
                lset scr $row [string range [lindex $scr $row] 0 [expr {$col - 1}]]
            } elseif {$n == 2} {
                lset scr $row ""
            }
        }
        n {
            if {$n == 6} {
                incr queries
                if {$t_query == 0} { set t_query [clock milliseconds] }
                if {$cpr} {
                    send -- "\033\[[expr {$row + 1}];[expr {min($col, $cols - 1) + 1}]R"
                }
            }
        }
    }
}

proc feed {data} {
    global st par row col srow scol armed t_query cpr_wait
    foreach ch [split $data ""] {
        switch -- $st {
            norm {
                if {$ch eq "\033"} {
                    set st esc
                } elseif {$ch eq "\n"} {
                    lf
                    set armed 1
                } elseif {$ch eq "\r"} {
                    set col 0
                } elseif {$ch eq "\b"} {
                    if {$col > 0} { incr col -1 }
                } elseif {$ch eq "\t"} {
                    set col [expr {($col / 8 + 1) * 8}]
                } elseif {[scan $ch %c] >= 32} {
                    if {$t_query > 0 && $cpr_wait < 0} {
                        set cpr_wait [expr {[clock milliseconds] - $t_query}]
                    }
                    putc $ch
                }
            }
            esc {
                if {$ch eq "\["} {
                    set st csi
                    set par ""
                } elseif {$ch eq "(" || $ch eq ")"} {
                    set st skip1
                } else {
                    if {$ch eq "7"} { set srow $row; set scol $col }
                    if {$ch eq "8"} { set row $srow; set col $scol }
                    set st norm
                }
            }
            skip1 { set st norm }
            csi {
                if {[string match {[0-9;?]} $ch]} {
                    append par $ch
                } else {
                    csi $par $ch
                    set st norm
                }
            }
        }
    }
}

proc snap {file} {
    global scr
    set f [open $file w]
    fconfigure $f -encoding utf-8
    foreach l $scr { puts $f [string trimright $l] }
    close $f
}

proc dump {} {
    global out scr sb pi pairs queries cpr_wait
    snap $out
    set f [open "$out.full" w]
    fconfigure $f -encoding utf-8
    foreach l [concat $sb $scr] { puts $f [string trimright $l] }
    close $f
    set f [open "$out.stats" w]
    puts $f "queries=$queries"
    puts $f "cpr_wait_ms=$cpr_wait"
    puts $f "answered=[expr {$pi / 2}]/[expr {[llength $pairs] / 2}]"
    close $f
}

proc try_answer {} {
    global st armed pi pairs scr row col out
    if {$st ne "norm" || !$armed || $pi >= [llength $pairs]} { return }
    set pat [lindex $pairs $pi]
    set left [string range [lindex $scr $row] 0 [expr {$col - 1}]]
    set k [string length $pat]
    if {[string range $left end-[expr {$k - 1}] end] ne $pat} { return }
    set ans [lindex $pairs [expr {$pi + 1}]]
    incr pi 2
    set armed 0
    snap "$out.[expr {$pi / 2}]"
    send -- "$ans\r"
}

set stty_init "rows $rows columns $cols"
eval spawn -noecho $cmd
expect {
    -re ".+" {
        feed $expect_out(0,string)
        try_answer
        exp_continue
    }
    timeout { dump; puts stderr "timeout"; exit 99 }
    eof
}
dump
catch wait result
if {[lindex $result 4] eq "CHILDKILLED"} {
    if {[lindex $result 5] eq "SIGINT"} { exit 130 }
    exit 129
}
exit [lindex $result 3]
EOF
}

# Default pty size for card tests (a test sets another height
# explicitly: run_vt -r N). 40 rows: the lens menu (~35 rows) with the card
# header does not fit, which also checks the screen redraw after an
# overflow (CARD_OVERFLOW); the camera menu fits, the usual path.
VT_ROWS=40
VT_COLS=100

# Runs glasser on folder $1/d in the terminal emulator (see
# write_vt_expect_script) with answers $3…; $2: whether to answer CSI 6n.
# Options go before $1: -r N is the pty height instead of VT_ROWS, -o OPT a
# glasser option (after the folder), -a with decoration (GLASSER_NO_ART=0),
# -e K=V an environment variable. Screens go to $1/screen*, the raw pty stream
# to $1/exp.log. Returns glasser's exit code (99 on timeout; 97 if
# glasser exited with 0 but not every answer was given: an expected prompt
# never appeared).
run_vt() {
    local rows="$VT_ROWS" opt="" envs=("GLASSER_NO_ART=$GLASSER_NO_ART")
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r) rows="$2"; shift 2 ;;
            -o) opt="$2"; shift 2 ;;
            -a) envs+=("GLASSER_NO_ART=0"); shift ;;
            -e) envs+=("$2"); shift 2 ;;
            *)  break ;;
        esac
    done
    local tmp="$1" cpr="$2" rc=0 answered
    shift 2
    [[ -f "$tmp/vt.exp" ]] || write_vt_expect_script "$tmp/vt.exp"
    if [[ -n "$opt" ]]; then
        env "${envs[@]}" expect "$tmp/vt.exp" "$rows" "$VT_COLS" "$cpr" "$tmp/screen" \
            4 "$BASH_BIN" "$GLASSER" "$tmp/d" "$opt" "$@" >"$tmp/exp.log" 2>&1 || rc=$?
    else
        env "${envs[@]}" expect "$tmp/vt.exp" "$rows" "$VT_COLS" "$cpr" "$tmp/screen" \
            3 "$BASH_BIN" "$GLASSER" "$tmp/d" "$@" >"$tmp/exp.log" 2>&1 || rc=$?
    fi
    [[ $rc -eq 0 ]] || return "$rc"
    answered=$(sed -n 's/^answered=//p' "$tmp/screen.stats" 2>/dev/null)
    if [[ -z "$answered" || "${answered%/*}" != "${answered#*/}" ]]; then
        printf '  ✗ not all answers given: %s\n' "${answered:-no screen.stats}" >&2
        return 97
    fi
    return 0
}

# Checks that file $1 has exactly $2 lines matching ERE $3.
# On mismatch prints ✗ with label $4 and the file, returns 1.
expect_lines() {
    local file="$1" want="$2" re="$3" label="$4" got
    got=$(grep -Ec -- "$re" "$file")
    if [[ "$got" != "$want" ]]; then
        printf '  ✗ %s: expected %s lines "%s", found %s (%s):\n' \
               "$label" "$want" "$re" "$got" "$(basename "$file")" >&2
        cat "$file" >&2
        return 1
    fi
    return 0
}

# Checks that file $1 has consecutive lines matching ERE $3, $4, …
# (one per line, no gaps or insertions). expect_lines counts lines but
# does not see their order or blank lines between them.
# On mismatch prints ✗ with label $2 and the file, returns 1.
expect_block() {
    local file="$1" label="$2"
    shift 2
    if ! awk 'BEGIN { n = ARGC - 2; for (i = 1; i <= n; i++) { re[i] = ARGV[i + 1]; delete ARGV[i + 1] } }
              { line[NR] = $0 }
              END {
                  for (s = 1; s + n - 1 <= NR; s++) {
                      for (i = 1; i <= n && line[s + i - 1] ~ re[i]; i++) ;
                      if (i > n) exit 0
                  }
                  exit 1
              }' "$file" "$@"; then
        printf '  ✗ %s: no consecutive lines (%s):\n' "$label" "$(basename "$file")" >&2
        printf '    "%s"\n' "$@" >&2
        cat "$file" >&2
        return 1
    fi
    return 0
}

# Code $1 of a run (run_interactive, run_vt, run_tmux) must be 0; otherwise
# prints ✗ (with label $3, if given) and the tail of log $2, returns 1.
expect_rc0() {
    local rc="$1" log="$2" label="${3:-}"
    [[ $rc -eq 0 ]] && return 0
    printf '  ✗ %src=%d\n' "${label:+$label: }" "$rc" >&2
    tail -20 "$log" >&2
    return 1
}

# Screen without card leftovers: no header, summary, prompts or menus.
# Applied to the screen after all groups are collapsed.
expect_no_card_leftovers() {
    local file="$1" label="$2"
    expect_lines "$file" 0 \
        '^EXIF:|^\[Group |Accept\?|Choose a (camera|lens)|^Number \[|^ *0\) (Back|Skip group)' \
        "$label: card leftovers"
}

# Card mode, one group, "Y" (stdout is a TTY, the terminal answers
# CSI 6n): the scan phase is replaced by the banner, the card collapsed into
# a line and nothing of it is left even in scroll-back, writing goes through
# the progress bar, tags written.
check_tty_cards() {
    need_expect || return "$SKIP_RC"
    local tmp
    tmp=$(new_tmpdir)
    mkdir "$tmp/d"
    cp "$SCRIPT_DIR/samples/Fuji + Konica/_DSF1160.JPG" "$tmp/d/a.JPG"
    printf 'tmp: %s\n' "$tmp"

    local errs=0 rc=0
    run_vt "$tmp" 1 '> ' y 'Y/n]: ' y || rc=$?
    expect_rc0 "$rc" "$tmp/exp.log" || errs=$((errs+1))
    if ! grep -aq $'\033\\[J' "$tmp/exp.log"; then
        printf '  ✗ no card wipe (CSI J): are cards off?\n' >&2
        errs=$((errs+1))
    fi
    # Screen 1 is the "Accept?" moment: the card really is drawn.
    expect_lines "$tmp/screen.1" 1 '^EXIF:' 'card drawn' || errs=$((errs+1))
    expect_lines "$tmp/screen.1" 1 'Accept\?' 'card drawn' || errs=$((errs+1))
    local full="$tmp/screen.full"
    expect_lines "$full" 0 '^Analyzing:' 'scan phase replaced by the banner' || errs=$((errs+1))
    expect_lines "$full" 1 '^◉  glasser  ·  d  ·  1 file$' 'banner' || errs=$((errs+1))
    expect_lines "$full" 1 '^✓ Fujifilm X-T4 \+ Konica Hexanon AR 57mm F1\.4 \(1 file\)$' \
        'collapsed card' || errs=$((errs+1))
    expect_no_card_leftovers "$full" 'scroll-back' || errs=$((errs+1))
    expect_lines "$full" 1 '100% \(1/1\) a\.JPG$' 'progress bar' || errs=$((errs+1))
    check_tag "$tmp/d/a.JPG" LensModel "Hexanon AR 57mm F1.4" || errs=$((errs+1))

    return "$errs"
}

# Card mode, two groups: group 1 "Y", group 2 "n" → camera menu
# (Enter keeps) → lens menu (does not fit the screen, redraw after
# overflow) → canon-fd-55 → "Y". On the screen at the
# "Apply the plan?" moment: the banner and two collapsed lines once each,
# no card leftovers; after the correction the group header is not doubled;
# tags written per the corrected choice.
check_tty_cards_correct() {
    need_expect || return "$SKIP_RC"
    local tmp
    tmp=$(new_tmpdir)
    prepare_interactive "$tmp"
    printf 'tmp: %s\n' "$tmp"

    local errs=0 rc=0 pos
    pos=$(lens_menu_pos canon-fd-55)
    run_vt "$tmp" 1 '> ' y  '> ' n  ']: ' ''  ']: ' "$pos"  '> ' y  'Y/n]: ' y || rc=$?
    expect_rc0 "$rc" "$tmp/exp.log" || errs=$((errs+1))
    # Screen 4 is the lens menu, 5 "Accept?" after the correction,
    # 6 "Apply the plan?".
    expect_lines "$tmp/screen.4" 1 '^ *0\) Back$' 'lens menu' || errs=$((errs+1))
    expect_lines "$tmp/screen.5" 1 '^\[Group 2/2\]' 'header after correction' || errs=$((errs+1))
    expect_lines "$tmp/screen.5" 1 '^EXIF:' 'header after correction' || errs=$((errs+1))
    expect_lines "$tmp/screen.5" 1 '^  Lens:    Canon FD 55mm f/1\.2 S\.S\.C\.' \
        'summary after correction' || errs=$((errs+1))
    expect_lines "$tmp/screen.5" 0 'Choose a|^Number \[' 'menu wiped' || errs=$((errs+1))
    local plan="$tmp/screen.6"
    expect_lines "$plan" 1 '^◉  glasser  ·  d  ·  2 files  ·  2 groups$' 'banner' || errs=$((errs+1))
    expect_lines "$plan" 1 '^✓ Group 1/2: Nikon Z f \+ Carl Zeiss Jena Biotar 58mm f/2 \(1 file\)$' \
        'collapsed group 1' || errs=$((errs+1))
    expect_lines "$plan" 1 '^✓ Group 2/2: Fujifilm X-T4 \+ Canon FD 55mm f/1\.2 S\.S\.C\. \(1 file\)$' \
        'collapsed group 2' || errs=$((errs+1))
    expect_no_card_leftovers "$plan" 'plan screen' || errs=$((errs+1))
    # The lens menu did not fit: after the clear at the start, a screen redraw
    # (wipe from home without ED 2, see ANSI_WIPE_SCREEN in glasser).
    local wipes
    wipes=$(grep -ao $'\033\\[H\033\\[K\033\\[B\033\\[J\033\\[H' "$tmp/exp.log" | wc -l | tr -d ' ')
    if [[ "$wipes" -lt 1 ]]; then
        printf '  ✗ no screen redraw after overflow\n' >&2
        errs=$((errs+1))
    fi
    check_tag "$tmp/d/nikon.JPG" LensModel "Biotar 58mm f/2" || errs=$((errs+1))
    check_tag "$tmp/d/fuji.JPG"  LensModel "FD 55mm f/1.2 S.S.C." || errs=$((errs+1))

    return "$errs"
}

# Card mode: "n" → "0" in the camera menu (back to "Accept?") →
# "s" skips group 1, group 2 "Y". The skipped group's file is
# untouched, collapsed lines once each, no card leftovers even
# in scroll-back (the camera menu fits the screen). Then "q" at the very first
# prompt: "Cancelled", rc 0, nothing written.
check_tty_cards_skip() {
    need_expect || return "$SKIP_RC"
    local tmp
    tmp=$(new_tmpdir)
    prepare_interactive "$tmp"
    printf 'tmp: %s\n' "$tmp"
    local md5_nikon
    md5_nikon=$(md5 -q "$tmp/d/nikon.JPG")

    local errs=0 rc=0
    run_vt "$tmp" 1 '> ' n  ']: ' 0  '> ' s  '> ' y  'Y/n]: ' y || rc=$?
    expect_rc0 "$rc" "$tmp/exp.log" || errs=$((errs+1))
    expect_lines "$tmp/screen.3" 1 '^> ?$' '"Back" returned to "Accept?"' || errs=$((errs+1))
    expect_lines "$tmp/screen.3" 0 'Choose a|^Number \[' 'menu wiped' || errs=$((errs+1))
    local full="$tmp/screen.full"
    expect_lines "$full" 1 '^⤳ Group 1/2: skipped \(1 file\)$' 'collapsed group 1' || errs=$((errs+1))
    expect_lines "$full" 1 '^✓ Group 2/2: Fujifilm X-T4 \+ Konica Hexanon AR 57mm F1\.4 \(1 file\)$' \
        'collapsed group 2' || errs=$((errs+1))
    expect_no_card_leftovers "$full" 'scroll-back' || errs=$((errs+1))
    if [[ "$(md5 -q "$tmp/d/nikon.JPG")" != "$md5_nikon" ]]; then
        printf '  ✗ file of the skipped group changed\n' >&2
        errs=$((errs+1))
    fi
    check_tag "$tmp/d/fuji.JPG" LensModel "Hexanon AR 57mm F1.4" || errs=$((errs+1))

    # "q": fresh copies, the same emulator.
    rm -rf "$tmp/d"
    prepare_interactive "$tmp"
    local md5_before
    md5_before=$(md5 -q "$tmp/d/nikon.JPG" "$tmp/d/fuji.JPG")
    rc=0
    run_vt "$tmp" 1 '> ' q || rc=$?
    expect_rc0 "$rc" "$tmp/exp.log" '"q"' || errs=$((errs+1))
    expect_lines "$tmp/screen" 1 '^Cancelled\. Nothing written\.$' '"q": cancel' || errs=$((errs+1))
    if [[ "$(md5 -q "$tmp/d/nikon.JPG" "$tmp/d/fuji.JPG")" != "$md5_before" ]]; then
        printf '  ✗ "q": files changed\n' >&2
        errs=$((errs+1))
    fi

    return "$errs"
}

# Card mode on a low screen (17 rows), two groups, "Y", "Y", "Y":
# the card starts at the bottom edge, and _card_make_room first scrolls
# the screen to make room. Without that the card anchor is taken before the
# scroll, and the wipe misses: card leftovers are visible in scroll-back.
# The height is within a narrow window. From below: at 100 columns the group
# card is planned at 16 rows (header of 4: blank, "[Group]", Nikon EXIF
# wrapped, plus SUMMARY_EPISODE_ROWS); at 15 and below it "does not fit",
# the redraw after overflow legitimately leaves copies in scroll-back, and
# the test fails on correct code. From above: at 18 and up no scroll is
# needed and the test does not catch a broken _card_make_room. 17 leaves a row of margin.
check_tty_cards_low() {
    need_expect || return "$SKIP_RC"
    local tmp
    tmp=$(new_tmpdir)
    prepare_interactive "$tmp"
    printf 'tmp: %s\n' "$tmp"

    local errs=0 rc=0
    run_vt -r 17 "$tmp" 1 '> ' y  '> ' y  'Y/n]: ' y || rc=$?
    expect_rc0 "$rc" "$tmp/exp.log" || errs=$((errs+1))
    local full="$tmp/screen.full"
    expect_lines "$full" 1 '^✓ Group 1/2: ' 'collapsed group 1' || errs=$((errs+1))
    expect_lines "$full" 1 '^✓ Group 2/2: ' 'collapsed group 2' || errs=$((errs+1))
    expect_no_card_leftovers "$full" 'scroll-back' || errs=$((errs+1))

    return "$errs"
}

# A card that does not fit the screen right from the start (12 rows: the group
# card at 100 columns is 14 rows, planned at 16): the anchor is marked
# stale at once (CARD_OVERFLOW in card_start_with_group_header), and
# collapsing redraws the screen: banner and collapsed lines. "s", "s":
# both groups skipped, glasser exits right after collapsing, and the
# last screen has the banner and both collapsed lines once each, no card
# leftovers. Without the mark the collapsed line would land on row 1, and the
# banner and past groups would remain only in scroll-back. Scroll-back is not
# checked here: a card taller than the screen goes there by itself, legitimately.
check_tty_cards_overflow_start() {
    need_expect || return "$SKIP_RC"
    local tmp
    tmp=$(new_tmpdir)
    prepare_interactive "$tmp"
    printf 'tmp: %s\n' "$tmp"

    local errs=0 rc=0
    run_vt -r 12 "$tmp" 1 '> ' s  '> ' s || rc=$?
    expect_rc0 "$rc" "$tmp/exp.log" || errs=$((errs+1))
    local scr="$tmp/screen"
    expect_lines "$scr" 1 '^◉  glasser  ·  d  ·  2 files  ·  2 groups$' 'banner' || errs=$((errs+1))
    expect_lines "$scr" 1 '^⤳ Group 1/2: skipped \(1 file\)$' 'collapsed group 1' || errs=$((errs+1))
    expect_lines "$scr" 1 '^⤳ Group 2/2: skipped \(1 file\)$' 'collapsed group 2' || errs=$((errs+1))
    expect_lines "$scr" 1 '^Nothing to apply' 'result' || errs=$((errs+1))
    expect_no_card_leftovers "$scr" 'last screen' || errs=$((errs+1))

    return "$errs"
}

# --no-confirm in card mode on a low screen (9 rows): a card without
# prompts (header + summary) collapses at once, and room for it is
# made in advance counting the two header lines "blank + [Group N/M]".
# Miscount them and the card scrolls the screen after the anchor is taken, the
# wipe misses, and "[Group 1/2]" stays in scroll-back. (The "summary +
# Accept?" episode does not catch this: SUMMARY_EPISODE_ROWS has its own two-row
# margin.) The height window where the miscount shows is 7…10; 9 is the middle.
check_tty_cards_no_confirm() {
    need_expect || return "$SKIP_RC"
    local tmp
    tmp=$(new_tmpdir)
    prepare_interactive "$tmp"
    printf 'tmp: %s\n' "$tmp"

    local errs=0 rc=0
    run_vt -r 9 -o --no-confirm "$tmp" 1 || rc=$?
    expect_rc0 "$rc" "$tmp/exp.log" || errs=$((errs+1))
    local full="$tmp/screen.full"
    expect_lines "$full" 1 '^✓ Group 1/2: Nikon Z f \+ ' 'collapsed group 1' || errs=$((errs+1))
    expect_lines "$full" 1 '^✓ Group 2/2: Fujifilm X-T4 \+ ' 'collapsed group 2' || errs=$((errs+1))
    expect_no_card_leftovers "$full" 'scroll-back' || errs=$((errs+1))
    check_tag "$tmp/d/nikon.JPG" LensModel "Biotar 58mm f/2" || errs=$((errs+1))
    check_tag "$tmp/d/fuji.JPG"  LensModel "Hexanon AR 57mm F1.4" || errs=$((errs+1))

    return "$errs"
}

# The terminal does not answer CSI 6n (Emacs shell, CI pty): glasser asks
# for the position exactly once, waits no more than ~1 s, turns cards off
# (linear output, no wipes or screen clears) and gets to writing instead
# of hanging on reading the answer. A hang is caught by the expect timeout.
# Limit 2500 ms: cpr_wait_ms is from the query to the next visible character,
# which is the "Scanning:" line that appears only after exiftool starts
# (perl) and reads the first file. read -t 1 itself is 1000 ms; the rest (usually
# ~100 ms) grows under the load of a parallel run; the margin keeps the test
# from flaking. Catches repeated queries and waiting on every redraw, but
# not a 2 s read timeout instead of 1.
check_tty_no_cpr() {
    need_expect || return "$SKIP_RC"
    local tmp
    tmp=$(new_tmpdir)
    mkdir "$tmp/d"
    cp "$SCRIPT_DIR/samples/Fuji + Konica/_DSF1160.JPG" "$tmp/d/a.JPG"
    printf 'tmp: %s\n' "$tmp"

    local errs=0 rc=0
    run_vt "$tmp" 0 '> ' y 'Y/n]: ' y || rc=$?
    expect_rc0 "$rc" "$tmp/exp.log" || errs=$((errs+1))
    if ! grep -qx 'queries=1' "$tmp/screen.stats"; then
        printf '  ✗ expected one CSI 6n:\n' >&2
        cat "$tmp/screen.stats" >&2
        errs=$((errs+1))
    fi
    local wait_ms
    wait_ms=$(sed -n 's/^cpr_wait_ms=//p' "$tmp/screen.stats")
    if ! [[ "$wait_ms" =~ ^[0-9]+$ ]] || [[ $wait_ms -gt 2500 ]]; then
        printf '  ✗ wait for the CSI 6n answer: %s ms (expected ≤ 2500)\n' "$wait_ms" >&2
        errs=$((errs+1))
    fi
    if grep -aqE $'\033\\[2?J' "$tmp/exp.log"; then
        printf '  ✗ screen wipe in linear mode\n' >&2
        errs=$((errs+1))
    fi
    expect_lines "$tmp/screen.full" 1 '^Analyzing:' 'linear output' || errs=$((errs+1))
    check_tag "$tmp/d/a.JPG" LensModel "Hexanon AR 57mm F1.4" || errs=$((errs+1))

    return "$errs"
}

# Aperture ring (the splash drawing is f/1.2–16, but the function is generic)
# for the range of every database lens: exactly
# BANNER_ART_W (23) columns, numbers decrease left to right, the rightmost is
# the max aperture, none larger than the min aperture, skipped is at most
# the stop right after the max aperture (and the most closed ones if they do not fit).
# glasser functions are taken from the script itself minus the last line (the main call).
check_banner_aperture_rows() {
    if [[ "$(tail -n 1 "$GLASSER")" != 'main "$@"' ]]; then
        printf '  ✗ the last line of glasser is not the main call\n' >&2
        return 1
    fi
    local out
    # shellcheck disable=SC2016  # expanded by the child bash
    out=$("$BASH_BIN" -c '
        eval "$(sed "\$d" "$1")"
        load_lens_db
        for ((l = 0; l < ${#LENS_IDS[@]}; l++)); do
            _banner_aperture_row "${LENS_MAX_APS[$l]}" "${LENS_MIN_APS[$l]}" 0
            printf "%s|%s|%s|%s\n" "${LENS_IDS[$l]}" "${LENS_MAX_APS[$l]}" \
                   "${LENS_MIN_APS[$l]}" "$BANNER_APER"
        done' _ "$GLASSER" 2>&1) || { printf '  ✗ %s\n' "$out" >&2; return 1; }
    local bad
    bad=$(printf '%s\n' "$out" | awk -F'|' '
        {
            row = $4
            if (length(row) != 23) { print $1 ": width " length(row) " \"" row "\""; next }
            n = split(row, t, " ")
            if (t[n] != $2) { print $1 ": rightmost " t[n] ", but max aperture " $2; next }
            for (i = 1; i <= n; i++) {
                if (t[i] + 0 > $3 + 0) { print $1 ": " t[i] " larger than min aperture " $3; next }
                if (i > 1 && t[i] + 0 >= t[i-1] + 0) { print $1 ": not decreasing \"" row "\""; next }
            }
            if (n < 4) print $1 ": only " n " numbers \"" row "\""
        }')
    if [[ -z "$out" || -n "$bad" ]]; then
        printf '  ✗ aperture ring:\n%s\n' "${bad:-(empty)}" >&2
        return 1
    fi
    return 0
}

# Splash in card mode (emulator, 40×100): drawing above the card,
# caption with folder and file count; the card is decorated (rule, EXIF
# by fields, check marks, keys in one line); while scanning, aperture frames
# before "Scanning:"; before "✓ Done." a "shutter click". A screen
# under 30 rows, --no-art and no color have their own variants.
check_banner() {
    need_expect || return "$SKIP_RC"
    local tmp
    tmp=$(new_tmpdir)
    mkdir "$tmp/d"
    cp "$SCRIPT_DIR/samples/Fuji + Konica/_DSF1160.JPG" "$tmp/d/a.JPG"
    printf 'tmp: %s\n' "$tmp"

    local errs=0 rc=0 full="$tmp/screen.full"
    run_vt -a "$tmp" 1 '> ' y 'Y/n]: ' y || rc=$?
    expect_rc0 "$rc" "$tmp/exp.log" 'splash' || errs=$((errs+1))
    expect_block "$full" 'splash' \
        '^    ∞   5   3   2  1\.5  1m$' \
        '^  ╭─┴───┴───┴───┴───┴───┴─╮   glasser$' \
        '^  │ (░▒){10}░ │   EXIF for manual lenses$' \
        '^  │16 11 8 5\.6 4 2\.8 2 1\.2│   ◉ d · 1 file$' \
        '^  ╰───────────────────────╯$' || errs=$((errs+1))
    expect_lines "$full" 1 '^    ∞   5' 'splash once' || errs=$((errs+1))
    # Decorated card (screen 1 is "Accept?"): rule, EXIF by
    # fields with wrapping, summary with check marks, keys in one line.
    expect_block "$tmp/screen.1" 'decorated card' \
        '^  (─){78}$' \
        '^    EXIF    Make/Model="FUJIFILM X-T4" · LensModel="Hexanon AR 57mm F1\.2"$' \
        '^            FocalLength=57mm · MaxAperture=f/1\.2$' \
        '^$' \
        '^    Camera  Fujifilm X-T4 +✓ detected$' \
        '^    Lens    Konica Hexanon AR 57mm F1\.4 +✓ guessed$' \
        '^            #2 · s/n 8143227$' \
        '^$' \
        '^  Accept\?   Y accept   n change   s skip   q quit$' \
        '^$' \
        '^  > ?$' || errs=$((errs+1))
    expect_lines "$tmp/screen.1" 0 '^EXIF:|\[Y\] accept' 'no old card' || errs=$((errs+1))
    expect_lines "$full" 0 '^◉  glasser' 'instead of the banner line' || errs=$((errs+1))
    expect_lines "$full" 0 'scanning…' 'scan phase caption replaced' || errs=$((errs+1))
    expect_lines "$full" 1 '^✓ Done\.$' 'result' || errs=$((errs+1))
    if ! grep -aqE '[·○◎◉] Scanning: ' "$tmp/exp.log"; then
        printf '  ✗ no aperture frames in the scan progress\n' >&2
        errs=$((errs+1))
    fi
    if ! grep -aq $'\r◉\r◎\r○\r·\r \r·\r○\r◎\r◉\r✓ Done.' "$tmp/exp.log"; then
        printf '  ✗ no "shutter click" before "✓ Done."\n' >&2
        errs=$((errs+1))
    fi
    if ! grep -aq $'\033\\[38;5;' "$tmp/exp.log"; then
        printf '  ✗ splash without color\n' >&2
        errs=$((errs+1))
    fi

    # NO_COLOR: the same drawing, but not a single SGR color.
    rm -f "$tmp"/screen*
    cp "$SCRIPT_DIR/samples/Fuji + Konica/_DSF1160.JPG" "$tmp/d/a.JPG"
    rc=0
    run_vt -a -e NO_COLOR=1 -o --dry-run "$tmp" 1 '> ' y || rc=$?
    expect_rc0 "$rc" "$tmp/exp.log" 'NO_COLOR' || errs=$((errs+1))
    expect_lines "$full" 1 '^  ╭─┴───┴───┴───┴───┴───┴─╮   glasser$' 'NO_COLOR: drawing' || errs=$((errs+1))
    if grep -aq $'\033\\[[0-9;]*m' "$tmp/exp.log"; then
        printf '  ✗ NO_COLOR: SGR in the output\n' >&2
        errs=$((errs+1))
    fi

    # Screen under 30 rows: banner line.
    rm -f "$tmp"/screen*
    rc=0
    run_vt -a -r 29 -o --dry-run "$tmp" 1 '> ' y || rc=$?
    expect_rc0 "$rc" "$tmp/exp.log" '29 rows' || errs=$((errs+1))
    expect_lines "$full" 1 '^◉  glasser  ·  d  ·  1 file$' '29 rows: banner line' || errs=$((errs+1))
    expect_lines "$full" 0 '╭─┴' '29 rows: no drawing' || errs=$((errs+1))

    # --no-art: banner line, no aperture frames and no click.
    rm -f "$tmp"/screen*
    rc=0
    run_vt -a -o --no-art "$tmp" 1 '> ' y 'Y/n]: ' y || rc=$?
    expect_rc0 "$rc" "$tmp/exp.log" '--no-art' || errs=$((errs+1))
    expect_lines "$full" 1 '^◉  glasser  ·  d  ·  1 file$' '--no-art: banner line' || errs=$((errs+1))
    expect_lines "$tmp/screen.1" 1 '^  \[Y\] accept' '--no-art: old-style card' || errs=$((errs+1))
    if grep -aqE '[○◎] Scanning|'$'\r''◎' "$tmp/exp.log"; then
        printf '  ✗ --no-art: aperture frames present\n' >&2
        errs=$((errs+1))
    fi

    return "$errs"
}

# Splash on a screen redraw: the lens menu (~35 rows) does not fit on 40
# rows, so the screen is redrawn with the banner. Decorated group headers:
# "◉ Group N of 2", all indented by 2 columns. On the plan screen there is
# exactly one drawing, collapsed groups once each, no card leftovers.
check_banner_redraw() {
    need_expect || return "$SKIP_RC"
    local tmp
    tmp=$(new_tmpdir)
    prepare_interactive "$tmp"
    printf 'tmp: %s\n' "$tmp"

    local errs=0 rc=0 pos plan
    pos=$(lens_menu_pos canon-fd-55)
    run_vt -a "$tmp" 1 '> ' y  '> ' n  ']: ' ''  ']: ' "$pos"  '> ' y  'Y/n]: ' y || rc=$?
    expect_rc0 "$rc" "$tmp/exp.log" || errs=$((errs+1))
    expect_lines "$tmp/screen.1" 1 '^  ◉ Group 1 of 2 · 1 file$' 'group 1 header' || errs=$((errs+1))
    expect_lines "$tmp/screen.5" 1 '^  ◉ Group 2 of 2 · 1 file$' 'group 2 header' || errs=$((errs+1))
    expect_lines "$tmp/screen.5" 1 '^    Lens    Canon FD 55mm f/1\.2 S\.S\.C\.$' \
        'summary after correction (no check mark)' || errs=$((errs+1))
    plan="$tmp/screen.6"
    expect_lines "$plan" 1 '^  ╭─┴───┴───┴───┴───┴───┴─╮   glasser$' 'splash on the plan screen' || errs=$((errs+1))
    expect_lines "$plan" 1 '^  │[ 0-9.]{23}│   ◉ d · 2 files · 2 groups$' 'splash caption' || errs=$((errs+1))
    expect_lines "$plan" 1 '^  ✓ Group 1/2: ' 'collapsed group 1' || errs=$((errs+1))
    expect_lines "$plan" 1 '^  ✓ Group 2/2: .*Canon FD 55mm' 'collapsed group 2' || errs=$((errs+1))
    expect_no_card_leftovers "$plan" 'plan screen' || errs=$((errs+1))
    local wipes
    wipes=$(grep -ao $'\033\\[H\033\\[K\033\\[B\033\\[J\033\\[H' "$tmp/exp.log" | wc -l | tr -d ' ')
    if [[ "$wipes" -lt 1 ]]; then
        printf '  ✗ no screen redraw after overflow\n' >&2
        errs=$((errs+1))
    fi
    check_tag "$tmp/d/fuji.JPG" LensModel "FD 55mm f/1.2 S.S.C." || errs=$((errs+1))

    return "$errs"
}

# Ctrl-C while the scan spinner spins (exiftool starts slowly):
# rc 130, the spinner line is wiped, the terminal gives EOF at once: the
# background spinner does not hold the pty or write after exit.
check_banner_spinner_sigint() {
    need_expect || return "$SKIP_RC"
    local tmp
    tmp=$(new_tmpdir)
    mkdir "$tmp/bin" "$tmp/d"
    write_fake_exiftool "$tmp/bin"
    : > "$tmp/d/a.JPG"
    cat > "$tmp/int.exp" <<'EOF'
set timeout 15
set env(TERM) xterm
set cmd $argv
eval spawn -noecho $cmd
expect {
    timeout { puts stderr "timeout: no spinner"; exit 99 }
    eof     { puts stderr "eof before the spinner"; exit 98 }
    -re {[◎◉] Scanning…} { send -- "\003" }
}
set t0 [clock milliseconds]
expect {
    timeout { puts stderr "timeout after Ctrl-C"; exit 99 }
    eof
}
puts "eof_ms=[expr {[clock milliseconds] - $t0}]"
catch wait result
if {[lindex $result 4] eq "CHILDKILLED"} {
    if {[lindex $result 5] eq "SIGINT"} { exit 130 }
    exit 129
}
exit [lindex $result 3]
EOF
    printf 'tmp: %s\n' "$tmp"

    local errs=0 rc=0 real ms
    real=$(command -v exiftool)
    PATH="$tmp/bin:$PATH" FAKE_REAL_EXIFTOOL="$real" FAKE_SCAN_DELAY=10 \
        GLASSER_NO_ART=0 \
        expect "$tmp/int.exp" "$BASH_BIN" "$GLASSER" --dry-run "$tmp/d" \
        >"$tmp/exp.log" 2>&1 || rc=$?
    if [[ $rc -ne 130 ]]; then
        printf '  ✗ expected rc=130, got %d\n' "$rc" >&2
        tail -5 "$tmp/exp.log" >&2
        errs=$((errs+1))
    fi
    # The eof_ms line is glued to the last pty output (no newline).
    ms=$(grep -ao 'eof_ms=[0-9]*' "$tmp/exp.log" | sed 's/^eof_ms=//')
    if ! [[ "$ms" =~ ^[0-9]+$ ]] || [[ $ms -gt 2000 ]]; then
        printf '  ✗ EOF %s ms after Ctrl-C (expected ≤ 2000)\n' "$ms" >&2
        errs=$((errs+1))
    fi
    # After the last spinner frame: the line is wiped.
    local log after
    log=$(<"$tmp/exp.log")
    after=${log##*Scanning…}
    if [[ "$log" != *Scanning…* || "$after" != *$'\033[2K'* ]]; then
        printf '  ✗ spinner line not wiped after Ctrl-C\n' >&2
        errs=$((errs+1))
    fi
    pkill -f "$tmp/bin/exiftool" 2>/dev/null || :

    return "$errs"
}

# The real terminal for card tests is tmux (if installed). The server
# is our own, on a private socket and without the user's config (-L, -f
# /dev/null); tmux_kill kills it (and cleanup_test_root on Ctrl-C).
# The user's tmux server is left alone.
TMUX_SOCK=""

need_tmux() {
    if ! command -v tmux >/dev/null 2>&1; then
        printf '  ⤳ no tmux\n'
        return 1
    fi
    return 0
}

# tmux on the run's socket. -u: UTF-8 regardless of locale; TMUX unset:
# otherwise inside someone's tmux session it would take the server as nested.
tmx() {
    env -u TMUX tmux -u -L "$TMUX_SOCK" -f /dev/null "$@"
}

# Kills the run's server and removes its socket file (kill-server
# leaves it).
tmux_kill() {
    [[ -n "$TMUX_SOCK" ]] || return 0
    local sock
    sock=$(tmx display -p '#{socket_path}' 2>/dev/null)
    tmx kill-server 2>/dev/null
    if [[ -n "$sock" && -S "$sock" ]]; then rm -f "$sock"; fi
    TMUX_SOCK=""
    return 0
}

# Waits (up to $2 s) until $1 returns 0; 0.1 s between attempts. Code 1:
# gave up waiting.
tmux_wait() {
    local cond="$1" limit=$(($2 * 10)) i
    for ((i=0; i<limit; i++)); do
        "$cond" && return 0
        sleep 0.1
    done
    return 1
}

# Conditions for tmux_wait. TM_PAT is the prompt without trailing spaces
# (capture-pane strips them): the line under the cursor ends with it, the cursor
# is not at the line start. TM_STATE is the screen and cursor at the answer: the
# next prompt is looked for only after the screen changed (the answer's echo),
# otherwise the same prompt would be found a second time.
TM_PAT=""
TM_STATE=""
TM_RC_FILE=""
_tm_state() {
    tmx display -p '#{cursor_x},#{cursor_y}'
    tmx capture-pane -p
}
_tm_at_prompt() {
    local x y line
    [[ -f "$TM_RC_FILE" ]] && return 0   # glasser exited: stop waiting
    read -r x y <<<"$(tmx display -p '#{cursor_x} #{cursor_y}')"
    [[ "$x" =~ ^[0-9]+$ && "$y" =~ ^[0-9]+$ && $x -gt 0 ]] || return 1
    line=$(tmx capture-pane -p -S "$y" -E "$y")
    [[ "$line" == *"$TM_PAT" ]]
}
_tm_changed() {
    [[ "$(_tm_state)" != "$TM_STATE" ]]
}
_tm_exited() {
    [[ -f "$TM_RC_FILE" ]]
}

# Runs glasser on folder $1/d in a real terminal (a separate tmux session
# of $2 rows × $3 columns) and answers "prompt (ASCII) / answer" pairs
# $4…, like run_vt. Screens: $1/screen.N (at the N-th answer), $1/screen
# (visible screen at the end), $1/screen.full (scroll-back + screen,
# capture-pane -S -). Returns glasser's exit code; 99: a prompt or
# glasser's exit was not seen (timeout), 97: glasser exited before
# all answers were given.
run_tmux() {
    local tmp="$1" rows="$2" cols="$3" n=0 pat ans rc
    shift 3
    TMUX_SOCK="glasser-test-$$-$RANDOM"
    TM_RC_FILE="$tmp/tm.rc"
    rm -f "$TM_RC_FILE"
    # Empty screens, so that the caller's checks have something to read even
    # on a failure before the snapshots (new-session did not start).
    : > "$tmp/screen"
    : > "$tmp/screen.full"
    # After glasser exits the window lives on (sleep): the screen and scroll-back
    # are captured after the exit, then tmux_kill kills the server.
    printf 'GLASSER_LANG=%q GLASSER_LENS_DB=%q %q %q %q\necho $? > %q\nexec sleep 600\n' \
        "$GLASSER_LANG" "$GLASSER_LENS_DB" "$BASH_BIN" "$GLASSER" "$tmp/d" "$TM_RC_FILE" > "$tmp/tm.sh"
    if ! tmx new-session -d -x "$cols" -y "$rows" "/bin/sh $(printf %q "$tmp/tm.sh")"; then
        printf '  ✗ tmux new-session did not start\n' >&2
        tmux_kill
        return 99
    fi
    while [[ $# -ge 2 ]]; do
        pat="$1" ans="$2"
        shift 2
        n=$((n+1))
        TM_PAT="${pat%"${pat##*[! ]}"}"
        if ! tmux_wait _tm_at_prompt 30; then
            printf '  ✗ tmux: prompt %d "%s" never came\n' "$n" "$pat" >&2
            tmx capture-pane -p > "$tmp/screen"
            tmux_kill
            return 99
        fi
        if [[ -f "$TM_RC_FILE" ]]; then
            printf '  ✗ tmux: glasser exited before prompt %d "%s"\n' "$n" "$pat" >&2
            tmx capture-pane -p > "$tmp/screen"
            tmx capture-pane -p -S - > "$tmp/screen.full"
            tmux_kill
            return 97
        fi
        tmx capture-pane -p > "$tmp/screen.$n"
        TM_STATE=$(_tm_state)
        [[ -z "$ans" ]] || tmx send-keys -l -- "$ans"
        tmx send-keys Enter
        if ! tmux_wait _tm_changed 30; then
            printf '  ✗ tmux: screen did not change after answer %d\n' "$n" >&2
            tmx capture-pane -p > "$tmp/screen"
            tmux_kill
            return 99
        fi
    done
    if ! tmux_wait _tm_exited 60; then
        printf '  ✗ tmux: glasser did not exit after the answers\n' >&2
        tmx capture-pane -p > "$tmp/screen"
        tmux_kill
        return 99
    fi
    tmx capture-pane -p > "$tmp/screen"
    tmx capture-pane -p -S - > "$tmp/screen.full"
    tmux_kill
    rc=$(cat "$TM_RC_FILE")
    return "${rc:-99}"
}

# Card mode in a real terminal (tmux), two groups, "Y", "Y", "Y",
# at two sizes: 16×100 and 24×80 (the default Terminal.app window size;
# EXIF wraps differently). 16 rows is exactly the planned card height
# at 100 columns (see check_tty_cards_low): the screen scrolls in advance
# all the way, the card anchor is row 1, and collapsing wipes from home. At
# 15 and below the card "does not fit" (redraw, copies in scroll-back are
# legitimate), at 17 and up the anchor is no longer on row 1. Code 0, tags written, no
# card leftovers on the last screen or anywhere in scroll-back
# (capture-pane -S -), and the banner and collapsed lines appear there once each and
# in a row (banner, blank line, group 1, group 2: an extra blank line means
# a wipe from the wrong row or CSI s/u instead of ESC 7/8 in Terminal.app). tmux
# (scroll-on-clear) pushes the screen into scroll-back on ED from home and ED 2;
# the emulator does not; glasser sends neither when wiping
# cards (see "does not start with ED at home" in glasser): collapsing is
# checked here, the redraw after overflow
# in check_tmux_cards_correct.
check_tmux_cards() {
    need_tmux || return "$SKIP_RC"
    cards_two_sizes run_tmux
}

# Body of check_tmux_cards and check_terminal_app_cards; $1 is the terminal
# runner (run_tmux or run_terminal_app, arguments as for run_tmux).
cards_two_sizes() {
    local runner="$1" tmp size rows cols errs=0 rc
    for size in 16x100 24x80; do
        rows=${size%x*}
        cols=${size#*x}
        tmp=$(new_tmpdir)
        prepare_interactive "$tmp"
        printf 'tmp (%s): %s\n' "$size" "$tmp"
        rc=0
        "$runner" "$tmp" "$rows" "$cols" '> ' y  '> ' y  'Y/n]: ' y || rc=$?
        expect_rc0 "$rc" "$tmp/screen" "$size" || errs=$((errs+1))
        expect_no_card_leftovers "$tmp/screen" "$size: last screen" || errs=$((errs+1))
        local full="$tmp/screen.full"
        expect_lines "$full" 1 '^◉  glasser  ·  d  ·  2 files  ·  2 groups$' "$size: banner" || errs=$((errs+1))
        expect_lines "$full" 1 '^✓ Group 1/2: Nikon Z f \+ ' "$size: collapsed group 1" || errs=$((errs+1))
        expect_lines "$full" 1 '^✓ Group 2/2: Fujifilm X-T4 \+ ' "$size: collapsed group 2" || errs=$((errs+1))
        expect_block "$full" "$size: banner and collapsed groups" \
            '^◉  glasser  ·  d  ·  2 files  ·  2 groups$' '^ *$' \
            '^✓ Group 1/2: Nikon Z f \+ ' '^✓ Group 2/2: Fujifilm X-T4 \+ ' || errs=$((errs+1))
        expect_no_card_leftovers "$full" "$size: scroll-back" || errs=$((errs+1))
        expect_lines "$full" 0 'Scanning' "$size: scan phase wiped" || errs=$((errs+1))
        check_tag "$tmp/d/nikon.JPG" LensModel "Biotar 58mm f/2" || errs=$((errs+1))
        check_tag "$tmp/d/fuji.JPG"  LensModel "Hexanon AR 57mm F1.4" || errs=$((errs+1))
    done

    return "$errs"
}

# Correction via the menu in a real terminal (tmux 24×80): group 2
# "n" → Enter → canon-fd-55 → "Y". The lens menu does not fit the screen and
# scrolls it: the top of the card (group 2 header, EXIF) and the menu start
# go into scroll-back by themselves (as in any terminal), exactly one copy each.
# The menu tail and the "Number [" prompt do not get there by natural scrolling
# (at 24×80 this is deterministic), so scroll-back is checked for exact
# counts: header and EXIF once each, "Accept?", "Number [" and the
# "0)" item never, no scan phase. This catches both ED at home / ED 2 on
# redraw (tmux would push the menu into scroll-back) and collapsing without
# a wipe (extra card copies). Screen 5 ("Accept?" after the
# correction) is redrawn after overflow: banner, collapsed
# group 1, group 2 header once each, menu wiped. The "Apply the
# plan?" screen is not checked: the plan itself takes all 24 rows. Tags per
# the corrected choice.
check_tmux_cards_correct() {
    need_tmux || return "$SKIP_RC"
    cards_correct run_tmux
}

# Body of check_tmux_cards_correct and check_terminal_app_correct; $1 as for
# cards_two_sizes.
cards_correct() {
    local runner="$1" tmp
    tmp=$(new_tmpdir)
    prepare_interactive "$tmp"
    printf 'tmp: %s\n' "$tmp"

    local errs=0 rc=0 pos
    pos=$(lens_menu_pos canon-fd-55)
    "$runner" "$tmp" 24 80 '> ' y  '> ' n  ']: ' ''  ']: ' "$pos"  '> ' y  'Y/n]: ' y || rc=$?
    expect_rc0 "$rc" "$tmp/screen" || errs=$((errs+1))
    local s5="$tmp/screen.5"
    expect_lines "$s5" 1 '^◉  glasser  ·  d  ·  2 files  ·  2 groups$' 'banner after redraw' || errs=$((errs+1))
    expect_lines "$s5" 1 '^✓ Group 1/2: Nikon Z f \+ ' 'collapsed group 1' || errs=$((errs+1))
    expect_lines "$s5" 1 '^\[Group 2/2\]' 'header after correction' || errs=$((errs+1))
    expect_lines "$s5" 1 '^EXIF:' 'header after correction' || errs=$((errs+1))
    expect_lines "$s5" 1 '^  Lens:    Canon FD 55mm f/1\.2 S\.S\.C\.' \
        'summary after correction' || errs=$((errs+1))
    expect_lines "$s5" 0 'Choose a|^Number \[' 'menu wiped' || errs=$((errs+1))
    expect_block "$s5" 'redraw: banner, group 1, group 2 header' \
        '^◉  glasser  ·  d  ·  2 files  ·  2 groups$' '^ *$' \
        '^✓ Group 1/2: Nikon Z f \+ ' '^ *$' '^\[Group 2/2\]' || errs=$((errs+1))
    local full="$tmp/screen.full"
    expect_lines "$full" 1 '^✓ Group 2/2: Fujifilm X-T4 \+ Canon FD 55mm f/1\.2 S\.S\.C\. ' \
        'collapsed group 2' || errs=$((errs+1))
    expect_block "$full" 'scroll-back: banner and collapsed groups' \
        '^◉  glasser  ·  d  ·  2 files  ·  2 groups$' '^ *$' \
        '^✓ Group 1/2: Nikon Z f \+ ' '^✓ Group 2/2: Fujifilm X-T4 \+ Canon ' || errs=$((errs+1))
    expect_lines "$full" 1 '^\[Group ' 'scroll-back: card header' || errs=$((errs+1))
    expect_lines "$full" 1 '^EXIF:' 'scroll-back: card EXIF' || errs=$((errs+1))
    expect_lines "$full" 0 'Accept\?|^Number \[|^ *0\) (Back|Skip group)' \
        'scroll-back: menus and prompts' || errs=$((errs+1))
    expect_lines "$full" 0 'Scanning' 'scroll-back: scan phase wiped' || errs=$((errs+1))
    check_tag "$tmp/d/nikon.JPG" LensModel "Biotar 58mm f/2" || errs=$((errs+1))
    check_tag "$tmp/d/fuji.JPG"  LensModel "FD 55mm f/1.2 S.S.C." || errs=$((errs+1))

    return "$errs"
}

# ── Real Terminal.app (on request only) ──
#
# The same scenarios as check_tmux_cards*, in a new Terminal.app window via
# osascript. Off by default (opens a window on the screen):
# GLASSER_TERMINAL_APP=1 or `make test-terminal`. Needs the
# "Automation → Terminal" permission for the app the run comes from;
# Accessibility is not needed: answers are sent by `do script … in tab` (text and Enter
# into the tab's tty input, as from the keyboard). The window has the "Basic" profile and
# a given size; only it is closed (by id), also on failure and
# Ctrl-C (ta_close from the EXIT trap).
TA_WIN=""        # id of the window opened by the check
TA_TTY=""        # tty of its tab
TA_LAUNCHED=0    # the run launched Terminal.app (then quit at the end)
TA_CLOSED=""     # ids of windows closed by the run (Terminal.app may still list them)
TA_PAT=""
TA_STATE=""
TA_DIR=""

# osascript with a limit of $1 s: without the "Automation" permission (a pending
# request) or with a hung Terminal.app the call fails instead of hanging. alarm
# survives exec.
ta_osa() {
    local limit="$1"
    shift
    perl -e 'alarm shift; exec @ARGV' "$limit" osascript "$@" 2>/dev/null
}

# Property $1 (contents: visible screen, history: scroll-back and screen)
# of the open window's tab.
ta_get() {
    ta_osa 10 -e "tell application \"Terminal\" to get $1 of tab 1 of window id $TA_WIN"
}

# Answer $1 and Enter into the tab's input.
ta_send() {
    ta_osa 10 -e 'on run argv' \
        -e 'tell application "Terminal" to do script (item 1 of argv) in tab 1 of window id ((item 2 of argv) as integer)' \
        -e 'end run' "$1" "$TA_WIN" >/dev/null
}

# Code 0: can run; 1: off or no Terminal.app (skip);
# 2: on, but Terminal.app does not respond (no permission).
need_terminal_app() {
    if [[ "${GLASSER_TERMINAL_APP:-}" != 1 ]]; then
        printf '  ⤳ Terminal.app: off (GLASSER_TERMINAL_APP=1 or make test-terminal)\n'
        return 1
    fi
    if [[ ! -d /System/Applications/Utilities/Terminal.app ]] || ! command -v osascript >/dev/null 2>&1; then
        printf '  ⤳ no Terminal.app or osascript\n'
        return 1
    fi
    if ! pgrep -xq Terminal; then
        # launch, not a first call: this way Terminal.app does not open
        # its default window.
        TA_LAUNCHED=1
        ta_osa 30 -e 'tell application "Terminal" to launch' >/dev/null
    fi
    if ! ta_osa 30 -e 'tell application "Terminal" to get version' >/dev/null; then
        printf '  ✗ Terminal.app did not answer AppleScript within 30 s: no permission\n' >&2
        printf '    "System Settings → Privacy & Security →\n' >&2
        printf '    Automation → Terminal" for the app the run comes from\n' >&2
        return 2
    fi
    return 0
}

# PIDs of the run window's processes: the window script ($TA_DIR/pid: sh, then
# `exec sleep`) and all its descendants (glasser, exiftool, …). Not looked up by tty
# name: the window outlives its pty, and by cleanup time the tty name may
# belong to someone else's tab, a tmux client, etc. So the root is taken
# only if it is still alive on the window's tty and is sh or sleep; otherwise empty.
ta_tree_pids() {
    local root comm level next p all=""
    root=$(cat "$TA_DIR/pid" 2>/dev/null)
    [[ "$root" =~ ^[0-9]+$ ]] || return 0
    [[ "$(ps -p "$root" -o tty= 2>/dev/null | tr -d ' ')" == "${TA_TTY#/dev/}" ]] || return 0
    comm=$(ps -p "$root" -o comm= 2>/dev/null)
    case "${comm##*/}" in
        sh|sleep) ;;
        *) return 0 ;;
    esac
    level=$root
    while [[ -n "$level" ]]; do
        all="$all $level"
        next=""
        for p in $level; do
            next="$next $(pgrep -P "$p" 2>/dev/null | tr '\n' ' ')"
        done
        [[ "$next" =~ [0-9] ]] || next=""
        level=$next
    done
    # shellcheck disable=SC2086  # PID list split into words, no extra spaces
    echo $all
}

# Sends signal $1 to the processes in list $2 (space-separated PIDs collected
# by ta_tree_pids beforehand) and waits (up to 2 s) for them to exit. The list is not
# rebuilt: after TERM the root is already dead, and ta_tree_pids would not find
# the descendants that outlived it. Code 1: some remain.
ta_kill_tree() {
    local sig="$1" pids="$2" p i alive
    [[ -z "$pids" ]] && return 0
    # shellcheck disable=SC2086  # PID list split into words
    kill "-$sig" $pids 2>/dev/null
    for ((i=0; i<20; i++)); do
        alive=0
        for p in $pids; do
            kill -0 "$p" 2>/dev/null && alive=1
        done
        [[ $alive -eq 0 ]] && return 0
        sleep 0.1
    done
    return 1
}

# From the EXIT trap (cleanup_test_root): closes the run window if it
# is still there, and quits Terminal.app if the run launched it and there are
# no other windows. Quitting happens only here: in the middle of a check it would make
# the next `do script` launch Terminal.app implicitly, with its default
# window. Windows are counted by id, not by visible: real windows
# can have visible false.
ta_close() {
    [[ -n "$TA_WIN" ]] && ta_close_window
    if [[ $TA_LAUNCHED -eq 1 ]]; then
        local ids id others=0
        if ids=$(ta_osa 10 -e 'tell application "Terminal" to get id of windows'); then
            for id in ${ids//,/ }; do
                [[ " $TA_CLOSED " == *" $id "* ]] || others=1
            done
            [[ $others -eq 1 ]] || ta_osa 10 -e 'tell application "Terminal" to quit' >/dev/null
        fi
        TA_LAUNCHED=0
    fi
    return 0
}

# Closes the run window (and only it) and resets TA_WIN/TA_TTY.
# The window's processes are ours (ta_tree_pids): close with live processes
# would hang a "Terminate processes?" sheet on the window, which cannot be
# closed without Accessibility (both the window and quitting Terminal.app get stuck).
# So kill them first, and if that fails, leave the window alone and
# report. Waits (up to 5 s) for the window to disappear (or to have no
# tabs left).
# Code 1: the window is not closed.
ta_close_window() {
    local win="$TA_WIN" end left="" rc=1 pids
    pids=$(ta_tree_pids)
    if ! ta_kill_tree TERM "$pids" && ! ta_kill_tree KILL "$pids"; then
        printf '  ✗ Terminal.app: processes of window %s (%s) did not exit, window left open\n' \
            "$win" "$TA_TTY" >&2
    else
        ta_osa 10 -e "tell application \"Terminal\" to close window id $win" >/dev/null
        end=$((SECONDS + 5))
        while [[ $SECONDS -lt $end ]]; do
            # visible is no good: open Terminal windows can have it
            # false too. A closed window may still be listed in windows, but has
            # no tabs anymore.
            left=$(ta_osa 10 -e "tell application \"Terminal\" to get (exists window id $win) and (exists tab 1 of window id $win)")
            [[ "$left" == true ]] || { rc=0; TA_CLOSED="$TA_CLOSED $win"; break; }
            sleep 0.2
        done
        [[ $rc -eq 0 ]] || printf '  ✗ Terminal.app: window %s did not close\n' "$win" >&2
    fi
    TA_WIN=""
    TA_TTY=""
    return "$rc"
}

# Waits (up to $2 s by the clock: each osascript takes a noticeable part of a second)
# until $1 returns 0. Code 1: gave up waiting.
ta_wait() {
    local cond="$1" end=$((SECONDS + $2))
    while [[ $SECONDS -lt $end ]]; do
        "$cond" && return 0
        sleep 0.2
    done
    return 1
}

# Conditions for ta_wait. Terminal.app does not report the cursor position: the prompt
# is the last non-empty screen line (glasser draws nothing below the cursor),
# it ends with TA_PAT (trailing spaces stripped from both).
_ta_file() { [[ -f "$TA_DIR/$1" ]]; }
_ta_started() { _ta_file pid; }
_ta_sized() { _ta_file size; }
_ta_exited() { _ta_file ta.rc; }
_ta_at_prompt() {
    _ta_exited && return 0   # glasser exited: stop waiting
    local last
    last=$(ta_get contents | awk 'NF { l = $0 } END { sub(/ +$/, "", l); print l }')
    [[ -n "$last" && "$last" == *"$TA_PAT" ]]
}
_ta_changed() {
    [[ "$(ta_get contents)" != "$TA_STATE" ]]
}

# Widths of glasser's glyphs in the terminal: each is printed at the line start,
# the cursor column is taken from the CSI 6n answer. Under bash $1, output is
# "glyph width" per line (width ? means no answer).
write_width_probe() {
    cat > "$1" <<'EOF'
saved=$(stty -g)
stty -icanon -echo
for g in a ◉ ○ ◎ ✓ ✗ ━ ─ █ ░ ▒ ╭ ╮ ╰ ╯ ┴ │ ∞ ← → · — … ⤳ × №; do
    printf '\r%s\033[6n' "$g" > /dev/tty
    r=""
    IFS= read -r -s -d R -t 2 r < /dev/tty
    c=${r##*;}
    if [[ "$c" =~ ^[0-9]+$ ]]; then
        printf '%s %d\n' "$g" $((c - 1))
    else
        printf '%s ?\n' "$g"
    fi
done
stty "$saved"
EOF
}

# Like run_tmux, but in a new Terminal.app window of $2 rows × $3 columns
# ("Basic" profile). The window script waits for the go file (the size is set after
# the window opens), measures glyph widths ($1/widths, write_width_probe),
# clears the screen and scroll-back (ED 2 + ED 3), writes `stty size` to $1/size and
# runs glasser. Screens: $1/screen.N, $1/screen (contents),
# $1/screen.full (history). Codes as for run_tmux; 96: wrong window
# size or the window did not open, 95: glasser finished but the window did not close.
run_terminal_app() {
    local tmp="$1" rows="$2" cols="$3" n=0 pat ans rc out
    shift 3
    TA_DIR="$tmp"
    : > "$tmp/screen"
    : > "$tmp/screen.full"
    write_width_probe "$tmp/probe.sh"
    printf '%s\n' \
        'echo $$ > pid.tmp && mv pid.tmp pid' \
        'while [ ! -f go ]; do sleep 0.1; done' \
        '/bin/bash probe.sh > widths' \
        "printf '\\033[H\\033[2J\\033[3J'" \
        'stty size > size.tmp && mv size.tmp size' \
        "$(printf 'GLASSER_LANG=%q GLASSER_LENS_DB=%q %q %q %q' "$GLASSER_LANG" "$GLASSER_LENS_DB" "$BASH_BIN" "$GLASSER" "$tmp/d")" \
        'echo $? > ta.rc.tmp && mv ta.rc.tmp ta.rc' \
        'exec sleep 600' > "$tmp/ta.sh"
    # A leading space keeps the command out of zsh history (HIST_IGNORE_SPACE).
    out=$(ta_osa 30 -e 'on run argv' \
        -e 'tell application "Terminal"' \
        -e 'set t to do script (item 1 of argv)' \
        -e 'set w to first window whose tabs contains t' \
        -e 'try' \
        -e 'set current settings of t to settings set "Basic"' \
        -e 'end try' \
        -e 'set number of rows of t to ((item 2 of argv) as integer)' \
        -e 'set number of columns of t to ((item 3 of argv) as integer)' \
        -e 'return ((id of w) as text) & " " & (tty of t)' \
        -e 'end tell' -e 'end run' \
        " cd $(printf %q "$tmp") && exec /bin/sh ta.sh" "$rows" "$cols")
    read -r TA_WIN TA_TTY <<<"$out"
    if ! [[ "$TA_WIN" =~ ^[0-9]+$ && "$TA_TTY" == /dev/* ]]; then
        printf '  ✗ Terminal.app: window did not open ("%s")\n' "$out" >&2
        TA_WIN=""
        return 96
    fi
    printf 'Terminal.app window %s, %s\n' "$TA_WIN" "$TA_TTY"
    if ! ta_wait _ta_started 30; then
        printf '  ✗ Terminal.app: window script did not start\n' >&2
        ta_get contents > "$tmp/screen"
        ta_close_window
        return 99
    fi
    touch "$tmp/go"
    if ! ta_wait _ta_sized 30; then
        printf '  ✗ Terminal.app: stty size never came\n' >&2
        ta_get contents > "$tmp/screen"
        ta_close_window
        return 99
    fi
    if [[ "$(cat "$tmp/size")" != "$rows $cols" ]]; then
        printf '  ✗ Terminal.app: window %s instead of %s %s (rows columns)\n' \
            "$(cat "$tmp/size")" "$rows" "$cols" >&2
        ta_close_window
        return 96
    fi
    while [[ $# -ge 2 ]]; do
        pat="$1" ans="$2"
        shift 2
        n=$((n+1))
        TA_PAT="${pat%"${pat##*[! ]}"}"
        if ! ta_wait _ta_at_prompt 30; then
            printf '  ✗ Terminal.app: prompt %d "%s" never came\n' "$n" "$pat" >&2
            ta_get contents > "$tmp/screen"
            ta_close_window
            return 99
        fi
        if _ta_exited; then
            printf '  ✗ Terminal.app: glasser exited before prompt %d "%s"\n' "$n" "$pat" >&2
            ta_get contents > "$tmp/screen"
            ta_get history > "$tmp/screen.full"
            ta_close_window
            return 97
        fi
        TA_STATE=$(ta_get contents)
        printf '%s\n' "$TA_STATE" > "$tmp/screen.$n"
        ta_send "$ans"
        if ! ta_wait _ta_changed 30; then
            printf '  ✗ Terminal.app: screen did not change after answer %d\n' "$n" >&2
            ta_get contents > "$tmp/screen"
            ta_close_window
            return 99
        fi
    done
    if ! ta_wait _ta_exited 60; then
        printf '  ✗ Terminal.app: glasser did not exit after the answers\n' >&2
        ta_get contents > "$tmp/screen"
        ta_close_window
        return 99
    fi
    ta_get contents > "$tmp/screen"
    ta_get history > "$tmp/screen.full"
    local closed=0
    ta_close_window || closed=1
    rc=$(cat "$tmp/ta.rc")
    [[ $closed -eq 0 ]] || return 95
    return "${rc:-99}"
}

# Glyph widths from $1/widths: all are 1 column (that is how glasser counts them
# when laying out cards and the progress bar). Width 2 would mean a profile with
# "East Asian Ambiguous: wide" and a broken layout.
expect_glyph_widths() {
    local file="$1" label="$2" bad
    bad=$(awk '$2 != 1' "$file")
    if [[ ! -s "$file" || -n "$bad" ]]; then
        printf '  ✗ %s: glyphs not 1 column wide (glyph width):\n%s\n' "$label" "${bad:-(no measurements)}" >&2
        return 1
    fi
    return 0
}

# need_terminal_app code → check code: off means skip, no
# permission means fail.
_ta_need_rc() {
    local rc=0
    need_terminal_app || rc=$?
    case $rc in
        0) return 0 ;;
        1) return "$SKIP_RC" ;;
        *) return 1 ;;
    esac
}

# check_tmux_cards in the real Terminal.app (16×100, 24×80) and glyph
# widths at each size. Only with GLASSER_TERMINAL_APP=1.
check_terminal_app_cards() {
    _ta_need_rc || return $?
    local errs=0 tmp
    cards_two_sizes run_terminal_app || errs=$?
    for tmp in "$TEST_ROOT"/case.*; do
        [[ -f "$tmp/widths" ]] || continue
        expect_glyph_widths "$tmp/widths" "glyph widths ($(cat "$tmp/size" 2>/dev/null))" || errs=$((errs+1))
    done
    return "$errs"
}

# check_tmux_cards_correct in the real Terminal.app (24×80): the redraw
# after the menu overflow, the place where terminals differ (ED
# into scroll-back). Only with GLASSER_TERMINAL_APP=1.
check_terminal_app_correct() {
    _ta_need_rc || return $?
    cards_correct run_terminal_app
}

# Expect scenario for Ctrl-C while reading the CSI 6n answer: argv =
# folder for files, command words. The command runs under bash with an INT trap (it
# survives Ctrl-C and takes stty -g before and after, in the same pty) via
# perl system(): bash would give 130 both on death by SIGINT and on exit 130,
# while perl tells them apart (during system() it ignores SIGINT itself). The terminal
# does not answer CSI 6n; 200 ms after the query (glasser waits for the answer up to
# 1 s) Ctrl-C goes into the pty. Files: tty.before, tty.after, rc ("sig=N exit=M":
# the signal that killed the command, and the exit code). Timeout gives 99, EOF before the query
# 98.
write_cpr_sigint_expect_script() {
    cat > "$1" <<'EOF'
set timeout 30
set env(TERM) xterm-256color
set dir [lindex $argv 0]
set cmd [lrange $argv 1 end]
spawn -noecho /bin/bash -c {trap : INT; stty -g > "$0/tty.before"; perl -e '$f = shift; system(@ARGV); open(my $h, ">", $f) or die; printf $h "sig=%d exit=%d\n", $? & 127, $? >> 8' "$0/rc" "$@"; stty -g > "$0/tty.after"} $dir {*}$cmd
expect {
    timeout { puts stderr "timeout: CSI 6n"; exit 99 }
    eof     { puts stderr "eof before CSI 6n"; exit 98 }
    -ex "\033\[6n" { after 200; send -- "\003" }
}
expect {
    timeout { puts stderr "timeout after Ctrl-C"; exit 99 }
    eof
}
EOF
}

# stty -g from file $1 without the PENDIN bit (0x20000000 in macOS lflag): the kernel
# sets it itself when ICANON is turned back on, and clears it on the next
# read; it is not part of the terminal settings.
stty_no_pendin() {
    local s
    s=$(cat "$1")
    if [[ "$s" =~ ^(.*:lflag=)([0-9a-f]+)(:.*)$ ]]; then
        printf '%s%x%s' "${BASH_REMATCH[1]}" \
            $((0x${BASH_REMATCH[2]} & ~0x20000000)) "${BASH_REMATCH[3]}"
    else
        printf '%s' "$s"
    fi
}

# Ctrl-C while glasser waits for the CSI 6n answer (stty -echo -icanon): the tty
# is restored as it was (stty -g before and after match), glasser died exactly
# of SIGINT rather than exiting with code 130 (set -e on a failed $(...)): only
# such a death is seen by the calling bash loop, which then stops. The read happens in
# $(...): without the parent's INT trap the tty was left without echo and canonical mode.
check_cpr_sigint() {
    need_expect || return "$SKIP_RC"
    local tmp
    tmp=$(new_tmpdir)
    mkdir "$tmp/d"
    cp "$SCRIPT_DIR/samples/Fuji + Konica/_DSF1160.JPG" "$tmp/d/a.JPG"
    write_cpr_sigint_expect_script "$tmp/cpr.exp"
    printf 'tmp: %s\n' "$tmp"

    local errs=0 rc=0 got
    expect "$tmp/cpr.exp" "$tmp" "$BASH_BIN" "$GLASSER" "$tmp/d" \
        >"$tmp/exp.log" 2>&1 || rc=$?
    expect_rc0 "$rc" "$tmp/exp.log" expect || errs=$((errs+1))
    got=$(cat "$tmp/rc" 2>/dev/null)
    if [[ "$got" != "sig=2 exit=0" ]]; then
        printf '  ✗ expected glasser to die of SIGINT ("sig=2 exit=0"), got "%s"\n' \
            "$got" >&2
        errs=$((errs+1))
    fi
    if [[ ! -s "$tmp/tty.before" || ! -s "$tmp/tty.after" ]]; then
        printf '  ✗ no stty -g before/after\n' >&2
        errs=$((errs+1))
    elif [[ "$(stty_no_pendin "$tmp/tty.before")" != "$(stty_no_pendin "$tmp/tty.after")" ]]; then
        printf '  ✗ tty not restored after Ctrl-C:\n  before: %s\n  after:  %s\n' \
            "$(cat "$tmp/tty.before")" "$(cat "$tmp/tty.after")" >&2
        errs=$((errs+1))
    fi

    return "$errs"
}

# Expect scenario for Ctrl-C: argv = file for glasser stdout ("-" means stdout
# is the pty too), marker, command words. TERM=dumb: no cards. After the
# marker (ASCII) it sends Ctrl-C into the pty: the whole foreground group
# gets SIGINT, as from the keyboard. Exit code as glasser's (130 for both exit 130
# and death by SIGINT), timeout gives 99, EOF before the marker 98.
write_sigint_expect_script() {
    cat > "$1" <<'EOF'
set timeout 30
set env(TERM) dumb
set env(GL_OUT) [lindex $argv 0]
set marker [lindex $argv 1]
set cmd [lrange $argv 2 end]
if {$env(GL_OUT) eq "-"} {
    eval spawn -noecho $cmd
} else {
    eval spawn -noecho /bin/sh -c {{exec "$0" "$@" >"$GL_OUT"}} $cmd
}
expect {
    timeout { puts stderr "timeout: $marker"; exit 99 }
    eof     { puts stderr "eof: $marker"; exit 98 }
    -ex $marker { send -- "\003" }
}
expect {
    timeout { puts stderr "timeout after Ctrl-C"; exit 99 }
    eof
}
catch wait result
if {[lindex $result 4] eq "CHILDKILLED"} {
    if {[lindex $result 5] eq "SIGINT"} { exit 130 }
    exit 129
}
exit [lindex $result 3]
EOF
}

# Fake exiftool in $1/exiftool (for the Ctrl-C tests). Scanning (-p):
# without FAKE_SCAN_SAMPLE the real exiftool, with it the sample's data line
# repeated for every file of the folder (fast, the files may be
# empty). FAKE_SCAN_DELAY is a pause before scanning (spinner). Writing: a mark in FAKE_WRITE_LOG, "FAKE-WRITE" on stderr and
# sleep, so Ctrl-C catches "exiftool" in the middle of writing.
write_fake_exiftool() {
    cat > "$1/exiftool" <<'EOF'
#!/bin/bash
case " $* " in
    *" -p "*)
        sleep "${FAKE_SCAN_DELAY:-0}"
        if [[ -z "${FAKE_SCAN_SAMPLE:-}" ]]; then
            exec "$FAKE_REAL_EXIFTOOL" "$@"
        fi
        us=$'\x1f'
        folder=${!#}
        line=$("$FAKE_REAL_EXIFTOOL" "${@:1:$#-1}" "$FAKE_SCAN_SAMPLE" 2>/dev/null | grep "$us")
        for f in "$folder"/*; do
            printf '%s%s%s\n' "$f" "$us" "${line#*"$us"}"
        done
        ;;
    *)
        printf 'w\n' >> "$FAKE_WRITE_LOG"
        printf 'FAKE-WRITE\n' >&2
        exec sleep 20
        ;;
esac
EOF
    chmod +x "$1/exiftool"
}

# Fake awk in $1/awk (for check_sigint_dry_run). A call from shquote
# (-v q=') with a path containing FAKE_AWK_BLOCK prints "FAKE-AWK" on stderr and
# hangs (sleep) until Ctrl-C kills it; everything else goes to the real awk.
write_fake_awk() {
    cat > "$1/awk" <<'EOF'
#!/bin/bash
for a in "$@"; do
    if [[ "$a" == "q='" ]]; then
        in=$(cat)
        if [[ "$in" == *"$FAKE_AWK_BLOCK"* ]]; then
            printf 'FAKE-AWK\n' >&2
            exec sleep 30
        fi
        printf '%s\n' "$in" | "$FAKE_REAL_AWK" "$@"
        exit
    fi
done
exec "$FAKE_REAL_AWK" "$@"
EOF
    chmod +x "$1/awk"
}

# Ctrl-C in --dry-run stops the run at once: rc 130 (death by SIGINT), not
# "keep printing with code 0" (no write INT trap is set in dry-run).
# No timing race: path f3' (the quote makes shquote call awk) is printed
# via the fake awk, which hangs until Ctrl-C arrives, so Ctrl-C
# is guaranteed to catch the path printing at f3', and f4, f5 cannot appear.
# With an INT trap in dry-run glasser would survive Ctrl-C and print f4, f5 (code 0).
check_sigint_dry_run() {
    need_expect || return "$SKIP_RC"
    local tmp i
    tmp=$(new_tmpdir)
    mkdir "$tmp/bin" "$tmp/d"
    write_fake_exiftool "$tmp/bin"
    write_fake_awk "$tmp/bin"
    write_sigint_expect_script "$tmp/int.exp"
    for i in 1 2 "3'" 4 5; do : > "$tmp/d/f$i.JPG"; done
    printf 'tmp: %s\n' "$tmp"

    # Real paths before PATH is replaced: otherwise the fake exiftool would call
    # itself.
    local errs=0 rc=0 real real_awk
    real=$(command -v exiftool)
    real_awk=$(command -v awk)
    PATH="$tmp/bin:$PATH" FAKE_REAL_EXIFTOOL="$real" \
        FAKE_REAL_AWK="$real_awk" FAKE_AWK_BLOCK="/d/f3'.JPG" \
        FAKE_SCAN_SAMPLE="$SCRIPT_DIR/samples/Nikon + Primoplan/_DSC0020.JPG" \
        FAKE_WRITE_LOG="$tmp/write.log" \
        expect "$tmp/int.exp" - FAKE-AWK \
            "$BASH_BIN" "$GLASSER" --dry-run --no-confirm "$tmp/d" \
            >"$tmp/exp.log" 2>&1 || rc=$?
    if [[ $rc -ne 130 ]]; then
        printf '  ✗ expected rc=130, got %d\n' "$rc" >&2
        tail -5 "$tmp/exp.log" >&2
        errs=$((errs+1))
    fi
    expect_lines "$tmp/exp.log" 1 '/d/f2\.JPG' 'paths before Ctrl-C printed' || errs=$((errs+1))
    expect_lines "$tmp/exp.log" 0 '/d/f[45]\.JPG' 'printing went on after Ctrl-C' || errs=$((errs+1))
    if [[ -e "$tmp/write.log" ]]; then
        printf '  ✗ dry-run started a write\n' >&2
        errs=$((errs+1))
    fi

    return "$errs"
}

# Ctrl-C in the middle of writing group 1 (of 2): rc 130, an "interrupted" message, and
# exiftool for group 2 is not started.
check_sigint_write() {
    need_expect || return "$SKIP_RC"
    local tmp
    tmp=$(new_tmpdir)
    prepare_interactive "$tmp"
    mkdir "$tmp/bin"
    write_fake_exiftool "$tmp/bin"
    write_sigint_expect_script "$tmp/int.exp"
    printf 'tmp: %s\n' "$tmp"

    local errs=0 rc=0 real
    real=$(command -v exiftool)
    PATH="$tmp/bin:$PATH" FAKE_REAL_EXIFTOOL="$real" FAKE_WRITE_LOG="$tmp/write.log" \
        expect "$tmp/int.exp" "$tmp/out.txt" FAKE-WRITE \
            "$BASH_BIN" "$GLASSER" --no-confirm "$tmp/d" \
            >"$tmp/exp.log" 2>&1 || rc=$?
    if [[ $rc -ne 130 ]]; then
        printf '  ✗ expected rc=130, got %d\n' "$rc" >&2
        tail -5 "$tmp/exp.log" >&2
        errs=$((errs+1))
    fi
    if ! grep -aq 'interrupted (Ctrl-C) in group 1' "$tmp/exp.log"; then
        printf '  ✗ no "interrupted (Ctrl-C) in group 1" message\n' >&2
        tail -5 "$tmp/exp.log" >&2
        errs=$((errs+1))
    fi
    local writes
    writes=$(wc -l < "$tmp/write.log" 2>/dev/null | tr -d ' ')
    if [[ "$writes" != "1" ]]; then
        printf '  ✗ expected one write run, got: %s\n' "${writes:-0}" >&2
        errs=$((errs+1))
    fi

    return "$errs"
}

# Menu: input with a leading zero is decimal. "0K" in the camera menu, where K
# is larger than the number of cameras and contains digit 8 or 9 (an octal reading is
# an arithmetic error), gives "invalid input, enter 0..<number of cameras>" (not a
# silent pick of some item); "0N" in the lens menu (N is the number of
# canon-fd-55) gives item N, not octal N. N ≥ 8, otherwise the octal and
# decimal readings would match. Numbers and range come from the database
# (--list-cameras, --list-lenses), not hard-coded: new database rows shift them.
check_menu_leading_zero() {
    need_expect || return "$SKIP_RC"
    local tmp
    tmp=$(new_tmpdir)
    mkdir "$tmp/d"
    cp "$SCRIPT_DIR/samples/Fuji + Konica/_DSF1160.JPG" "$tmp/d/a.JPG"
    write_expect_script "$tmp/run.exp"
    printf 'tmp: %s\n' "$tmp"

    local errs=0 rc=0 pos ncam cam bad
    pos=$(lens_menu_pos canon-fd-55)
    if ! [[ "$pos" =~ ^[0-9]+$ ]] || [[ $pos -lt 8 ]]; then
        printf '  ✗ canon-fd-55 menu number: "%s" (need ≥ 8)\n' "$pos" >&2
        return 1
    fi
    ncam=$(camera_menu_count)
    cam=$(camera_menu_pos fuji-xt4)
    if ! [[ "$ncam" =~ ^[0-9]+$ && "$cam" =~ ^[0-9]+$ ]] || [[ $ncam -lt 1 ]]; then
        printf '  ✗ camera menu: "%s" cameras, fuji-xt4 number "%s"\n' "$ncam" "$cam" >&2
        return 1
    fi
    # The first number larger than the camera count (and at least 8) with digit 8 or 9.
    bad=$((ncam + 1))
    [[ $bad -ge 8 ]] || bad=8
    until [[ "$bad" =~ [89] ]]; do bad=$((bad + 1)); done
    run_interactive "$tmp" \
        '> ' n  ']: ' "0$bad"  "enter 0..$ncam"$'\r' -  ']: ' "$cam"  ']: ' "0$pos" \
        '> ' y  'Y/n' n || rc=$?
    expect_rc0 "$rc" "$tmp/exp.log" expect || errs=$((errs+1))
    if ! grep -q '✓ Fujifilm X-T4 + Canon FD 55mm f/1.2 S.S.C.' "$tmp/out.txt"; then
        printf '  ✗ "0%s" did not pick item %s:\n' "$pos" "$pos" >&2
        cat "$tmp/out.txt" >&2
        errs=$((errs+1))
    fi

    return "$errs"
}

# "0" in the correction menu with a complete choice goes back to "Accept?",
# not out of the whole session, losing the decisions on past groups.
check_menu_cancel_back() {
    need_expect || return "$SKIP_RC"
    local tmp
    tmp=$(new_tmpdir)
    prepare_interactive "$tmp"
    printf 'tmp: %s\n' "$tmp"

    local errs=0 rc=0
    run_interactive "$tmp" \
        '> ' y  '> ' n  ']: ' 0  '> ' y  'Y/n' n || rc=$?
    expect_rc0 "$rc" "$tmp/exp.log" expect || errs=$((errs+1))
    if ! grep -q '0) Back' "$tmp/exp.log"; then
        printf '  ✗ no "0) Back" item in the menu\n' >&2
        errs=$((errs+1))
    fi
    # Both groups accepted, the plan reached; writing cancelled at "Apply".
    local committed
    committed=$(grep -c '^✓ Group [12]/2' "$tmp/out.txt")
    if [[ "$committed" != "2" ]]; then
        printf '  ✗ expected 2 accepted groups, found %s:\n' "$committed" >&2
        cat "$tmp/out.txt" >&2
        errs=$((errs+1))
    fi
    if ! grep -q '━━━ Write plan ━━━' "$tmp/out.txt"; then
        printf '  ✗ the plan was not reached\n' >&2
        errs=$((errs+1))
    fi

    return "$errs"
}

main() {
    if ! command -v exiftool >/dev/null 2>&1; then
        printf 'exiftool not found\n' >&2
        exit 1
    fi
    if [[ ! -f "$GLASSER" ]]; then
        printf 'glasser not found: %s\n' "$GLASSER" >&2
        exit 1
    fi
    # Required samples (samples/ is not in git). Without them the tests would fail
    # in bulk with "cp: No such file", and some would falsely pass.
    local f missing=0
    for f in "Fuji + Konica/_DSF1160.JPG" "Fuji + Konica/_DSF1160.RAF" \
             "Nikon + Primoplan/_DSC0020.JPG" "Nikon + Primoplan/_DSC0020.NEF"; do
        if [[ ! -f "$SCRIPT_DIR/samples/$f" ]]; then
            printf 'no sample: samples/%s\n' "$f" >&2
            missing=1
        fi
    done
    [[ $missing -eq 0 ]] || exit 2

    local bash_major
    # shellcheck disable=SC2016  # expanded by the child bash, not this one
    bash_major=$("$BASH_BIN" -c 'printf %s "${BASH_VERSINFO[0]}"' 2>/dev/null) || {
        printf 'bash for glasser does not run: %s\n' "$BASH_BIN" >&2
        exit 1
    }
    printf 'glasser under %s (bash %s), tests under bash %s\n' \
           "$BASH_BIN" "$bash_major" "${BASH_VERSINFO[0]}"
    if [[ "$bash_major" != "3" ]]; then
        printf 'warning: glasser is not under bash 3.2, so this run does not catch 3.2 regressions\n' >&2
    fi

    local tmp_base="${TMPDIR:-/tmp}"
    TEST_ROOT=$(mktemp -d "${tmp_base%/}/glasser-test.XXXXXX") || exit 1
    # EXIT removes TEST_ROOT; INT/TERM go through exit, so that the run
    # really stops and the EXIT trap runs.
    trap cleanup_test_root EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    run_case "Fuji X-T4 + Konica Hexanon → hexanon-57-14 (auto-detect, JPG+RAF)" check_fuji_konica
    run_case "Nikon Z f (Primoplan sample) → biotar-58 (auto-detect, JPG+NEF)" check_nikon_primoplan
    run_case "Cross: Nikon Z f + Hexanon"                        check_cross_nikon_with_hexanon
    run_case "Idempotency, Fuji"                                 check_idempotent_fuji
    run_case "Idempotency, Nikon (Nikon quantum is stable)"      check_idempotent_nikon
    run_case "detect_lens by FocalLength (step 2, no LensModel)" check_detect_by_focal
    run_case "detect_lens: LensInfo with empty MaxApertureValue" check_lensinfo_fallback
    run_case "Raw Nikon+Primoplan (adapter reports 50/1.5)"      check_unedit_nikon_primoplan
    run_case "Mixed folder: Fuji+Konica and Nikon+Primoplan together" check_mixed_two_groups
    run_case "Mixed folder: 3 groups (plan + summary)"           check_mixed_three_groups
    run_case "--dry-run multi-group (md5 unchanged, 2 commands)" check_dry_run_multi_group
    run_case "--no-confirm: unguessed group, nothing written"    check_no_confirm_atomic
    run_case "Retagging without a serial clears the old one"     check_retag_clears_serial
    run_case "Body XMP-aux:SerialNumber is not cleared"          check_keeps_body_serial_in_aux
    run_case "Unknown MakerNote group: error at load"            check_unknown_makernote_group
    run_case "EXIF line: fields do not shift with empty LensModel" check_exif_line_empty_lensmodel
    run_case "Ambiguous lens: error, not the first row"          check_ambiguous_lens
    run_case "Folder \"#roll\" as a relative path (-@ argfile)"  check_hash_folder
    run_case "File name with a newline stays out of the argfile" check_newline_filename
    run_case "exiftool error in a group does not stop the others" check_failed_group_continues
    run_case "Arguments: return codes and messages"              check_cli
    run_case "Localization: catalog covers every UI key"        check_l10n_catalog
    run_case "Localization: Russian UI and language selection"  check_l10n_ru
    run_case "LC_ALL=C: tables as under UTF-8"                   check_locale_c
    run_case "No terminal and no --no-confirm: rc != 0"          check_no_tty
    run_case "Interactive: \"s\" skips a group"                  check_interactive_skip
    run_case "Interactive: cancel (n, q) and Ctrl-D"             check_interactive_cancel
    run_case "TTY: cards and progress bar"                       check_tty_cards
    run_case "TTY: cards, 2 groups, correction via the menu"     check_tty_cards_correct
    run_case "TTY: cards, \"0\" back, \"s\" skip, \"q\""         check_tty_cards_skip
    run_case "TTY: cards at the bottom of the screen (scroll)"   check_tty_cards_low
    run_case "TTY: card does not fit the screen from the start"  check_tty_cards_overflow_start
    run_case "TTY: --no-confirm, cards on a low screen"          check_tty_cards_no_confirm
    run_case "TTY without a CSI 6n answer: linear output"        check_tty_no_cpr
    run_case "Ctrl-C while waiting for CSI 6n: tty restored"     check_cpr_sigint
    run_case "Splash: aperture ring of every database lens"      check_banner_aperture_rows
    run_case "Splash, spinner, click; NO_COLOR, 29 rows, --no-art" check_banner
    run_case "Splash on a screen redraw (overflow)"              check_banner_redraw
    run_case "Ctrl-C during the scan spinner: rc 130"            check_banner_spinner_sigint
    run_case "tmux: cards in a real terminal (16×100, 24×80)"    check_tmux_cards
    run_case "tmux: correction via the menu (24×80)"             check_tmux_cards_correct
    run_case "Terminal.app: cards (16×100, 24×80; on request)"   check_terminal_app_cards
    run_case "Terminal.app: correction via the menu (24×80; on request)" check_terminal_app_correct
    run_case "Ctrl-C in --dry-run: immediate exit, rc 130"       check_sigint_dry_run
    run_case "Ctrl-C while writing: the next group is not written" check_sigint_write
    run_case "Menu: leading zero is decimal input"               check_menu_leading_zero
    run_case "Menu: \"0\" goes back to the confirmation"         check_menu_cancel_back
    run_case "Many files in one group (GLASSER_LOAD_N)"          check_load_many_files

    printf '\n──────────\n'
    printf 'Pass: %d\nFail: %d\nSkip: %d\n' "$PASS" "$FAIL" "$SKIP"
    if [[ $FAIL -gt 0 ]]; then
        printf '\nFailed:\n'
        local name
        for name in "${FAILURES[@]}"; do
            printf '  - %s\n' "$name"
        done
        exit 1
    fi
}

main "$@"
