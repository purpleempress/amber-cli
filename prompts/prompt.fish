# fish port of prompts/prompt.bash -- keep in sync.
#
# Layout:  [user@host] /path<segments>
#          $   (or # when root)
#
# Faithful port of the canonical bash prompt. Differences are mechanical:
# fish uses set_color / printf for colours (it tracks non-printing width
# itself, so the bash \001\002 markers are NOT used), and exit status is
# $status (captured FIRST, before anything clobbers it).
#
# Colour reference (256-colour palette):
#   214 amber   208 orange   220 gold   245 grey
#    75 blue    113 green    196 red
#
# Colours are specified as 256-palette indices, so for exact parity with bash
# we emit raw `\e[38;5;Nm` sequences via printf rather than approximating with
# hex. __ambercli_color centralises that.

# ---------------------------------------------------------------------------
# colour helpers -- raw 256-colour SGR for exact parity with .bash_prompt.
# ---------------------------------------------------------------------------
function __ambercli_color --argument-names n
    printf '\e[38;5;%sm' $n
end

function __ambercli_reset
    printf '\e[0m'
end

# ---------------------------------------------------------------------------
# glyphs -- same table/rule as prompts/prompt.bash.
#   cross (nonzero exit): unicode ✘ / ascii x
#   hex   (docker compose): unicode ⬢ / ascii #
# ascii when $AMBERCLI_GLYPHS=ascii, OR when $AMBERCLI_GLYPHS unset AND the locale
# ($LC_ALL/$LC_CTYPE/$LANG) lacks UTF-8/utf8; otherwise unicode. Never font-detect.
# ---------------------------------------------------------------------------
function __ambercli_glyph --argument-names name
    set -l ascii 0
    if test "$AMBERCLI_GLYPHS" = ascii
        set ascii 1
    else if test -z "$AMBERCLI_GLYPHS"
        set -l loc "$LC_ALL"
        test -z "$loc"; and set loc "$LC_CTYPE"
        test -z "$loc"; and set loc "$LANG"
        if string match -qir 'utf-?8' -- "$loc"
            set ascii 0
        else
            set ascii 1
        end
    end
    switch $name
        case cross
            if test $ascii -eq 1; printf 'x'; else; printf '✘'; end
        case hex
            if test $ascii -eq 1; printf '#'; else; printf '⬢'; end
    end
end

# ---------------------------------------------------------------------------
# host colour -- cksum of the short hostname modulo the 22-entry palette,
# computed ONCE and cached in a universal-ish global. 196 (red) is never in
# the palette so the host colour can't be confused with error/root markers.
# ---------------------------------------------------------------------------
function __ambercli_host_color
    if not set -q __ambercli_host_color_cached
        set -l palette 39 45 75 81 111 113 141 147 170 178 208 209 213 214 215 220 76 80 110 168 176 180
        set -l h (hostname -s)
        set -l sum (printf '%s' $h | cksum | string split ' ')[1]
        set -l idx (math "$sum % "(count $palette))
        # fish lists are 1-based; the modulo result is 0-based.
        set -g __ambercli_host_color_cached $palette[(math $idx + 1)]
    end
    printf '%s' $__ambercli_host_color_cached
end

# ---------------------------------------------------------------------------
# segments -- appended in the same order as bash, each space-prefixed.
# ---------------------------------------------------------------------------

# docker compose: " <hex> up/total", green all-up / amber some-down / red all-down.
# single daemon call; parse state strings locally.
function __ambercli_docker_segment
    if not test -f docker-compose.yml -o -f compose.yaml -o -f docker-compose.yaml
        return
    end
    set -l out (docker compose ps -a --format '{{.State}}' 2>/dev/null)
    or return
    set -l total (count $out)
    test $total -gt 0; or return
    set -l up 0
    for s in $out
        test "$s" = running; and set up (math $up + 1)
    end
    set -l col 113 # all up
    test $up -lt $total; and set col 214 # some down
    test $up -eq 0; and set col 196 # all down
    __ambercli_color $col
    printf ' %s %s/%s' (__ambercli_glyph hex) $up $total
    __ambercli_reset
end

# git: branch (or short hash if detached) + "*" when dirty.
# untracked files do NOT count as dirty -- hand-rolled, NOT fish_git_prompt.
function __ambercli_git_segment
    set -l branch (git symbolic-ref --short HEAD 2>/dev/null)
    or set branch (git rev-parse --short HEAD 2>/dev/null)
    or return
    set -l dirty ""
    if not git diff --quiet 2>/dev/null; or not git diff --cached --quiet 2>/dev/null
        set dirty "*"
    end
    set -l col 113 # clean
    test -n "$dirty"; and set col 214 # dirty
    __ambercli_color $col
    printf ' %s%s' $branch $dirty
    __ambercli_reset
end

# python venv: blue " (name)" from $VIRTUAL_ENV basename.
function __ambercli_venv_segment
    test -n "$VIRTUAL_ENV"; or return
    __ambercli_color 75
    printf ' (%s)' (basename $VIRTUAL_ENV)
    __ambercli_reset
end

# ssh marker: orange " ssh" when $SSH_TTY/$SSH_CONNECTION set.
function __ambercli_ssh_segment
    if test -z "$SSH_TTY" -a -z "$SSH_CONNECTION"
        return
    end
    __ambercli_color 208
    printf ' ssh'
    __ambercli_reset
end

# root warning: red " root" when id -u == 0.
function __ambercli_root_segment
    test (id -u) -eq 0; or return
    __ambercli_color 196
    printf ' root'
    __ambercli_reset
end

# ---------------------------------------------------------------------------
# the prompt -- $status MUST be captured FIRST, before anything clobbers it.
# layout:  [user@host] /path<segments>\n<indicator>
# ---------------------------------------------------------------------------
function fish_prompt
    set -l code $status

    set -l host (__ambercli_host_color)

    # [user@host]  -- brackets and @ grey 245, user in brand purple (141),
    # host in its per-host colour.
    __ambercli_color 245
    printf '['
    __ambercli_color 141
    printf '%s' (whoami)
    __ambercli_color 245
    printf '@'
    __ambercli_color $host
    printf '%s' (hostname -s)
    __ambercli_color 245
    printf ']'
    __ambercli_reset

    # space + path in blue 75. We replicate bash's \w exactly: the FULL cwd,
    # with a leading $HOME collapsed to ~ (NOT fish's abbreviating prompt_pwd).
    set -l wd $PWD
    if test "$wd" = "$HOME"
        set wd '~'
    else if string match -q -- "$HOME/*" "$wd"
        set wd '~'(string sub -s (math (string length "$HOME") + 1) -- "$wd")
    end
    printf ' '
    __ambercli_color 75
    printf '%s' "$wd"
    __ambercli_reset

    # segments, in order
    if test $code -ne 0
        __ambercli_color 196
        printf ' %s %s' (__ambercli_glyph cross) $code
        __ambercli_reset
    end
    __ambercli_docker_segment
    __ambercli_git_segment
    __ambercli_venv_segment
    __ambercli_ssh_segment
    __ambercli_root_segment

    # newline + indicator (# root else $), in brand purple (141, matches AMBERCLI_ACCENT)
    printf '\n'
    __ambercli_color 141
    if test (id -u) -eq 0
        printf '#'
    else
        printf '$'
    end
    __ambercli_reset
    printf ' '
end

# ---------------------------------------------------------------------------
# right prompt -- dim clock HH:MM; if $VIRTUAL_ENV set, also show its basename.
# ---------------------------------------------------------------------------
function fish_right_prompt
    set -l txt (date +%H:%M)
    test -n "$VIRTUAL_ENV"; and set txt "$txt "(basename $VIRTUAL_ENV)
    set_color -d
    printf '%s' $txt
    set_color normal
end
