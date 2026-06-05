# shellcheck shell=bash
# cat .bash_prompt
# ~/.bash_prompt  :3
# context-aware colourful prompt
#
# save this file ON THE BOX as ~/.bash_prompt (leading dot!), then load it
# from ~/.bashrc with:
#   [[ -f ~/.bash_prompt ]] && source ~/.bash_prompt
# reload while tweaking with:  source ~/.bash_prompt
#
# colour reference (256-colour palette):
#   214 amber   208 orange   220 gold   245 grey
#    75  blue   113 green    196 red

# ---------------------------------------------------------------------------
# colour escapes for the segments.
#
# THESE MUST BE REAL CONTROL BYTES, not "\[\e[..m\]" notation. here's why:
# bash builds the prompt in two passes -- (1) decode PS1 backslash escapes
# (\u \h \[ \e ...), then (2) expand ${_ctx} into the result. by pass 2 the
# escape-decoding is already done, so any "\[" / "\e" sitting inside $_ctx
# would just print literally. $'...' (ANSI-C quoting) bakes the real bytes
# in at assignment time: \e -> ESC, \001/\002 -> the non-printing markers
# that \[ and \] decode to. so these Just Work when substituted into PS1.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2034  # _C_* are used inside the single-quoted PS1 below,
# which shellcheck can't see through; they are NOT unused.
_C_accent=$'\001\e[38;5;141m\002'   # brand purple (matches lib's AMBERCLI_ACCENT)
_C_amber=$'\001\e[38;5;214m\002'
_C_orange=$'\001\e[38;5;208m\002'
_C_blue=$'\001\e[38;5;75m\002'
_C_green=$'\001\e[38;5;113m\002'
_C_red=$'\001\e[38;5;196m\002'
_C_reset=$'\001\e[0m\002'

# ---------------------------------------------------------------------------
# glyphs -- resolved ONCE at load time, matching the amber glyph table exactly.
#   cross (nonzero exit): unicode ✘ / ascii x
#   hex   (docker compose): unicode ⬢ / ascii #
# rule: ascii when $AMBERCLI_GLYPHS=ascii, OR when $AMBERCLI_GLYPHS is unset AND the
# locale ($LC_ALL/$LC_CTYPE/$LANG) lacks UTF-8/utf8; otherwise unicode. Never
# font-detect. This is a STANDALONE copy of the table (we deliberately do NOT
# source lib: its readonly vars would break `source ~/.bash_prompt` reload).
# ---------------------------------------------------------------------------
if [[ "${AMBERCLI_GLYPHS:-}" == ascii ]]; then
    _G_ascii=1
elif [[ -z "${AMBERCLI_GLYPHS:-}" ]]; then
    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
        *UTF-8* | *utf8* | *UTF8* | *utf-8*) _G_ascii=0 ;;
        *) _G_ascii=1 ;;
    esac
else
    _G_ascii=0
fi
if [[ "$_G_ascii" == 1 ]]; then
    _G_cross='x'
    _G_hex='#'
else
    _G_cross='✘'
    _G_hex='⬢'
fi
unset _G_ascii

# ---------------------------------------------------------------------------
# host colour -- derived from the hostname so every box has its own stable,
# distinct identity. computed ONCE at load time (the hostname can't change
# mid-session), then baked into _C_host with the same real-byte treatment as
# the static colours above.
#
# the palette is a hand-picked set of 256-colour codes that all read well on
# a dark terminal; 196 (red) is deliberately left out so the host colour can
# never be confused with the error / root markers. cksum gives a cheap, stable
# hash of the short hostname (\h == ${HOSTNAME%%.*}); modulo picks a slot.
# ---------------------------------------------------------------------------
_host_palette=(39 45 75 81 111 113 141 147 170 178 208 209 213 214 215 220 76 80 110 168 176 180)
_host_hash=$(printf '%s' "${HOSTNAME%%.*}" | cksum)
_host_hash=${_host_hash%% *}
_host_color=${_host_palette[$(( _host_hash % ${#_host_palette[@]} ))]}
_C_host=$'\001\e[38;5;'"${_host_color}m"$'\002'

# ---------------------------------------------------------------------------
# segments -- each appends to $_ctx. cheap ones (env/file reads) are free;
# docker + git shell out but you've clocked them well under 30ms.
# ---------------------------------------------------------------------------

# docker compose: shows " up/total", green / amber / red.
# single daemon call -- parse state strings locally.
_docker_context() {
    [[ -f docker-compose.yml || -f compose.yaml || -f docker-compose.yaml ]] || return
    local out total up col
    out=$(docker compose ps -a --format '{{.State}}' 2>/dev/null) || return
    total=$(grep -c .          <<<"$out")
    up=$(grep -c '^running$'   <<<"$out")
    [[ "$total" -gt 0 ]] || return
    col=$_C_green                              # all up
    [[ "$up" -lt "$total" ]] && col=$_C_amber  # some down
    [[ "$up" -eq 0 ]]        && col=$_C_red    # all down
    _ctx+="${col} ${_G_hex} ${up}/${total}${_C_reset}"
}

# git: branch (or short hash if detached) + "*" when dirty.
# untracked files do NOT count as dirty -- keeps the dot meaningful.
_git_context() {
    local branch dirty col
    branch=$(git symbolic-ref --short HEAD 2>/dev/null) \
        || branch=$(git rev-parse --short HEAD 2>/dev/null) \
        || return
    dirty=""
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        dirty="*"
    fi
    col=$_C_green                        # clean
    [[ -n "$dirty" ]] && col=$_C_amber   # dirty
    _ctx+="${col} ${branch}${dirty}${_C_reset}"
}

# python venv: free, the var is already set.
_venv_context() {
    [[ -n "${VIRTUAL_ENV:-}" ]] || return
    _ctx+="${_C_blue} (${VIRTUAL_ENV##*/})${_C_reset}"
}

# ssh marker: "you are not on your laptop." pure env check.
_ssh_context() {
    [[ -n "${SSH_TTY:-}${SSH_CONNECTION:-}" ]] || return
    _ctx+="${_C_orange} ssh${_C_reset}"
}

# root warning: $EUID is a bash builtin, free.
_root_context() {
    [[ "$EUID" -eq 0 ]] || return
    _ctx+="${_C_red} root${_C_reset}"
}

# ---------------------------------------------------------------------------
# EXPERIMENTAL bash "right prompt" -- OFF by default.
#
# bash has no native right prompt. Enable with $AMBERCLI_BASH_RIGHT_PROMPT=1.
# This is best-effort and FRAGILE: on terminal resize or when the left line
# wraps, the saved-cursor trick can leave the clock in the wrong place. It is
# intentionally opt-in so the default prompt stays byte-identical to before.
#
# Technique: we print BEFORE PS1 is rendered (from PROMPT_COMMAND), while the
# cursor sits at column 0 of the fresh prompt line. We ESC 7 (save cursor),
# jump to a column near the right edge, print a dim HH:MM (+ venv basename),
# then ESC 8 (restore) so PS1 draws normally from column 0. We degrade
# gracefully: if $COLUMNS is unset or too small to place the text cleanly, we
# print nothing at all (no garbage, no half-clipped clock).
# ---------------------------------------------------------------------------
_bash_right_prompt() {
    [[ "${AMBERCLI_BASH_RIGHT_PROMPT:-}" == 1 ]] || return
    local cols=${COLUMNS:-0}
    [[ "$cols" =~ ^[0-9]+$ ]] || return
    local txt
    txt=$(date +%H:%M)
    [[ -n "${VIRTUAL_ENV:-}" ]] && txt+=" (${VIRTUAL_ENV##*/})"
    local len=${#txt}
    # need room for the text plus a little breathing space; bail if too narrow.
    (( cols >= len + 2 )) || return
    local startcol=$(( cols - len + 1 ))
    # ESC 7 save, move to (row stays) col, dim text, reset, ESC 8 restore.
    printf '\e7\e[%dG\e[2m%s\e[0m\e8' "$startcol" "$txt"
}

# ---------------------------------------------------------------------------
# assembler -- runs before every prompt draw.
# `local code=$?` MUST be the first line: anything else clobbers $?.
# ---------------------------------------------------------------------------
_prompt_context() {
    local code=$?
    _ctx=""
    [[ "$code" -ne 0 ]] && _ctx+="${_C_red} ${_G_cross} ${code}${_C_reset}"
    _docker_context
    _git_context
    _venv_context
    _ssh_context
    _root_context
    _bash_right_prompt
}
PROMPT_COMMAND=_prompt_context

# ---------------------------------------------------------------------------
# the prompt itself.
# SINGLE quotes -- ${_ctx} must expand fresh at display time, every draw.
# PS1's own escapes use \[\e..\] notation: that's correct, they get decoded
# in pass 1. only the $_ctx *contents* needed the real-byte treatment above.
# layout:  [user@host] /path <segments>
#          $
# ---------------------------------------------------------------------------
PS1='\[\e[38;5;245m\]['"${_C_accent}"'\u\[\e[38;5;245m\]@'"${_C_host}"'\h\[\e[38;5;245m\]]\[\e[0m\] \[\e[38;5;75m\]\w\[\e[0m\]${_ctx}\n'"${_C_accent}"'\$\[\e[0m\] '
