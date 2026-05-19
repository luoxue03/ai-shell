#!/usr/bin/env zsh
# disable-kaku-ai.zsh — Disable Kaku terminal's built-in # AI handler
#
# Source this in ~/.zshrc AFTER Kaku's zsh integration to permanently
# disable Kaku's # → AI query feature. Useful when you prefer ai-shell
# or want to use # as a plain comment.
#
# Usage in ~/.zshrc:
#   [[ -f "$HOME/.config/ai-shell/disable-kaku-ai.zsh" ]] && \
#       source "$HOME/.config/ai-shell/disable-kaku-ai.zsh"
#
# This file is a no-op in non-Kaku terminals.

# Override Kaku's # handler by replacing its function body.
# Works because zsh resolves widget functions by name at call time —
# the new body takes effect immediately, no need to re-register the widget.
_disable_kaku_ai_apply() {
    if (( ${+functions[_kaku_ai_query_accept_line]} )); then
        _kaku_ai_query_accept_line() {
            POSTDISPLAY=
            zle .accept-line
        }
        typeset -g _KAKU_AI_DISABLED=1
    fi
    precmd_functions=("${precmd_functions[@]:#_disable_kaku_ai_apply}")
}

# Defer to precmd so this runs AFTER Kaku's own _kaku_ai_query_register_widget
precmd_functions+=(_disable_kaku_ai_apply)
