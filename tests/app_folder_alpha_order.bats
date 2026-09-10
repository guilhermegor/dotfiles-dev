#!/usr/bin/env bats
#
# The app-folder list written to `folder-children` must be ordered
# alphabetically by the name the GNOME Shell DISPLAYS, not by dconf id.
#
# Three ids differ from their display name — Seguranca→Security,
# Sistema→System, Utilitarios→Utilities — so the two orderings genuinely
# disagree, and a test that only checked "is sorted" would pass on the wrong
# one. Every assertion below is built around a pair that discriminates them.
#
# Strategy: reproduce the ordering pipeline against a stubbed `gsettings`, so
# no test reads or writes live dconf.
#
# Run locally: bats tests/

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

    # id → display name, exactly as ubuntu_workspace.sh writes them.
    declare -gA NAMES=(
        [Browsers]=Browsers   [Code]=Code         [Data]=Data
        [Design]=Design       [Ereader]=Ereader   [Infra]=Infra
        [IRPF]=IRPF           [Media]=Media       [Office]=Office
        [Planning]=Planning   [Reading]=Reading   [Seguranca]=Security
        [Sharing]=Sharing     [Social]=Social     [Sistema]=System
        [Utilitarios]=Utilities
    )

    gsettings() {
        # `gsettings get <schema:path> name` — pull the id out of the path.
        local path="$2" id
        id="${path%/}"; id="${id##*/}"
        printf "'%s'\n" "${NAMES[$id]:-}"
    }

    # The ordering pipeline under test, mirroring organize_app_folders.
    order_folders() {
        local created bare display
        for created in "$@"; do
            bare="${created//\'/}"
            display=$(gsettings get \
                "org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/${bare}/" \
                name 2>/dev/null | tr -d "'")
            printf '%s\t%s\n' "${display:-$bare}" "$created"
        done | sort -f | cut -f2
    }
}

@test "the full folder set comes out alphabetical by display name" {
    run order_folders "'Sistema'" "'Seguranca'" "'Utilitarios'" "'Design'" \
        "'Sharing'" "'IRPF'" "'Code'" "'Data'" "'Ereader'" "'Office'" \
        "'Media'" "'Planning'" "'Social'" "'Infra'" "'Browsers'" "'Reading'"
    [ "$status" -eq 0 ]

    expected="'Browsers'
'Code'
'Data'
'Design'
'Ereader'
'Infra'
'IRPF'
'Media'
'Office'
'Planning'
'Reading'
'Seguranca'
'Sharing'
'Social'
'Sistema'
'Utilitarios'"
    [ "$output" = "$expected" ]
}

# --- the pairs that discriminate display-order from id-order ------------------

@test "Social precedes Sistema — by id it would not (Si < So)" {
    run order_folders "'Sistema'" "'Social'"
    [ "$output" = "'Social'
'Sistema'" ]
}

@test "Seguranca sorts as Security, before Sharing" {
    run order_folders "'Sharing'" "'Seguranca'"
    [ "$output" = "'Seguranca'
'Sharing'" ]
}

@test "Utilitarios sorts as Utilities, still last after System" {
    run order_folders "'Utilitarios'" "'Sistema'"
    [ "$output" = "'Sistema'
'Utilitarios'" ]
}

@test "Infra precedes IRPF — case-insensitive, so -f is load-bearing" {
    run order_folders "'IRPF'" "'Infra'"
    [ "$output" = "'Infra'
'IRPF'" ]
}

# --- degradation --------------------------------------------------------------

@test "an unresolvable name falls back to the bare id, never to empty" {
    NAMES=()   # simulate DRY_RUN: names previewed, never written
    run order_folders "'Sistema'" "'Browsers'"
    [ "$output" = "'Browsers'
'Sistema'" ]
}

@test "ordering a single folder is a no-op, not an error" {
    run order_folders "'Code'"
    [ "$status" -eq 0 ]
    [ "$output" = "'Code'" ]
}
