#!/usr/bin/env zsh
# ai-shell.zsh — Standalone AI command generator for any terminal
# Usage: type "# <query>" and press Enter to generate shell commands via LLM
# Automatically disabled inside Kaku (which has its own implementation)

# Skip if running inside Kaku terminal
[[ -n "${WEZTERM_PANE:-}" ]] && return 0

# ── Config ────────────────────────────────────────────────────────────
_ai_shell_load_config() {
    typeset -g AI_SHELL_API_KEY=""
    typeset -g AI_SHELL_MODEL=""
    typeset -g AI_SHELL_BASE_URL=""
    typeset -g AI_SHELL_TIMEOUT=15

    local config_file="$HOME/.config/ai-shell/config"
    [[ -f "$config_file" ]] && source "$config_file"

    if [[ -z "$AI_SHELL_API_KEY" ]]; then
        local toml="$HOME/.config/kaku/assistant.toml"
        if [[ -f "$toml" ]]; then
            _ai_shell_parse_toml() { grep -E "^$1\s*=" "$2" | head -1 | sed 's/^[^=]*=[[:space:]]*//;s/^"//;s/"[[:space:]]*$//'; }
            AI_SHELL_API_KEY=$(_ai_shell_parse_toml api_key "$toml")
            AI_SHELL_MODEL=$(_ai_shell_parse_toml model "$toml")
            AI_SHELL_BASE_URL=$(_ai_shell_parse_toml base_url "$toml")
            unfunction _ai_shell_parse_toml 2>/dev/null
        fi
    fi
}

_ai_shell_load_config

# ── Safety Checks ─────────────────────────────────────────────────────
_ai_shell_is_dangerous() {
    local cmd="${1:l}"
    local check="$cmd"
    [[ "$check" == sudo\ * ]] && check="${check#sudo }"
    check="${check## }"

    [[ "$cmd" == *':(){ :|:& };:'* ]] && return 0
    [[ "$check" == rm\ * && ("$check" == *-rf* || "$check" == *-fr*) ]] && return 0
    [[ "$check" == mkfs* ]] && return 0
    [[ "$check" == dd\ if=* ]] && return 0
    [[ "$check" == shutdown* || "$check" == reboot* || "$check" == poweroff* ]] && return 0
    [[ "$check" == git\ reset\ --hard* ]] && return 0
    [[ "$check" == git\ clean\ * && "$check" == *-f* && "$check" == *d* ]] && return 0
    return 1
}

_ai_shell_sanitize_command() {
    local cmd="$1"
    cmd="${cmd#\`\`\`*$'\n'}"
    cmd="${cmd%$'\n'\`\`\`}"
    cmd="${cmd#\`\`\`*}"
    cmd="${cmd%\`\`\`}"
    cmd="${cmd## }" ; cmd="${cmd%% }"
    cmd="${cmd%%$'\n'*}"
    [[ "$cmd" == '$ '* ]] && cmd="${cmd#\$ }"
    cmd="${cmd## }" ; cmd="${cmd%% }"
    REPLY="$cmd"
}

# ── UI Colors ─────────────────────────────────────────────────────────
_c_purple='\e[38;5;141m'
_c_grey='\e[38;5;244m'
_c_green='\e[38;5;114m'
_c_cyan='\e[38;5;81m'
_c_red='\e[1;31m'
_c_yellow='\e[1;33m'
_c_bold='\e[1m'
_c_dim='\e[2m'
_c_reset='\e[0m'

# ── Core ──────────────────────────────────────────────────────────────
_ai_shell_generate() {
    local query="$1"

    local cwd="${PWD}"
    local git_branch=""
    git_branch=$(command git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null) || true

    local user_content="Request: ${query}\nWorking directory: ${cwd}"
    [[ -n "$git_branch" ]] && user_content+="\nGit branch: ${git_branch}"

    local system_prompt='You are a shell command assistant. Return exactly one JSON object (no markdown, no code fences) with this structure:
{"options":[{"summary":"<中文说明，不超过30字>","command":"<single executable shell command>","why":"<中文解释为什么用这个命令>"},{"summary":"<中文说明>","command":"<alternative command>","why":"<中文解释>"}]}
Rules:
- Provide exactly 2 options, from simple to advanced
- summary must be in Chinese, concise
- command must be a single executable shell command, no aliases like ll
- If you cannot produce a safe command, set command to empty string
- why must be in Chinese, one sentence'

    local payload
    payload=$(command jq -n \
        --arg model "$AI_SHELL_MODEL" \
        --arg sys "$system_prompt" \
        --arg user "$user_content" \
        '{model: $model, stream: false, messages: [{role: "system", content: $sys}, {role: "user", content: $user}]}')

    local api_url="${AI_SHELL_BASE_URL%/}/chat/completions"

    # Show thinking indicator
    print -n "\n  ${_c_purple}${_c_reset} ${_c_grey}AI thinking...${_c_reset}"

    # Synchronous API call
    local raw_response
    raw_response=$(command curl -sS --fail \
        --connect-timeout 3 \
        --max-time "$AI_SHELL_TIMEOUT" \
        "$api_url" \
        -H "Authorization: Bearer $AI_SHELL_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null)
    local curl_exit=$?

    # Clear thinking line
    print -n "\r\e[2K\e[1A\e[2K"

    if [[ $curl_exit -ne 0 || -z "$raw_response" ]]; then
        print "\n  ${_c_purple}╭─ AI Shell${_c_reset}  ${_c_red}请求失败${_c_reset}"
        print "  ${_c_purple}╰─${_c_reset} ${_c_grey}检查网络连接和 API 配置${_c_reset}\n"
        BUFFER=""
        return
    fi

    # Parse outer response
    local content
    content=$(echo "$raw_response" | command jq -r '.choices[0].message.content // empty' 2>/dev/null)

    if [[ -z "$content" ]]; then
        print "\n  ${_c_purple}╭─ AI Shell${_c_reset}  ${_c_red}响应为空${_c_reset}"
        print "  ${_c_purple}╰─${_c_reset} ${_c_grey}无法生成命令${_c_reset}\n"
        BUFFER=""
        return
    fi

    # Extract inner JSON (tolerant of surrounding text)
    local json_str
    json_str=$(echo "$content" | command sed -n '/{/,/}/p')
    [[ -z "$json_str" ]] && json_str="$content"

    # Parse options array
    local opt_count
    opt_count=$(echo "$json_str" | command jq -r '.options | length' 2>/dev/null)

    if [[ -z "$opt_count" || "$opt_count" == "0" ]]; then
        # Fallback: try single-command format
        local single_cmd single_summary
        single_cmd=$(echo "$json_str" | command jq -r '.command // empty' 2>/dev/null)
        single_summary=$(echo "$json_str" | command jq -r '.summary // empty' 2>/dev/null)
        if [[ -n "$single_cmd" ]]; then
            _ai_shell_sanitize_command "$single_cmd"; single_cmd="$REPLY"
            print "\n  ${_c_purple}╭─ AI Shell${_c_reset}  ${_c_bold}${single_summary}${_c_reset}"
            print "  ${_c_purple}╰─${_c_reset} ${_c_green}${single_cmd}${_c_reset}\n"
            BUFFER="$single_cmd"
            CURSOR=${#BUFFER}
            return
        fi
        print "\n  ${_c_purple}╭─ AI Shell${_c_reset}  ${_c_red}无法生成命令${_c_reset}"
        print "  ${_c_purple}╰─${_c_reset} ${_c_grey}请尝试换个方式描述${_c_reset}\n"
        BUFFER=""
        return
    fi

    # Build options display
    local -a commands summaries whys dangers
    local i _cmd _summary _why
    for (( i=0; i<opt_count && i<3; i++ )); do
        _cmd=$(echo "$json_str" | command jq -r ".options[$i].command // empty" 2>/dev/null)
        _summary=$(echo "$json_str" | command jq -r ".options[$i].summary // empty" 2>/dev/null)
        _why=$(echo "$json_str" | command jq -r ".options[$i].why // empty" 2>/dev/null)
        _ai_shell_sanitize_command "$_cmd"; _cmd="$REPLY"
        [[ -z "$_cmd" ]] && continue
        commands+=("$_cmd")
        summaries+=("$_summary")
        whys+=("$_why")
        _ai_shell_is_dangerous "$_cmd" && dangers+=("1") || dangers+=("0")
    done

    if [[ ${#commands[@]} -eq 0 ]]; then
        print "\n  ${_c_purple}╭─ AI Shell${_c_reset}  ${_c_red}无法生成命令${_c_reset}"
        print "  ${_c_purple}╰─${_c_reset} ${_c_grey}请尝试换个方式描述${_c_reset}\n"
        BUFFER=""
        return
    fi

    # Render selection UI
    print ""
    print "  ${_c_purple}╭─ AI Shell ───────────────────────────────────╮${_c_reset}"
    for (( i=1; i<=${#commands[@]}; i++ )); do
        local num_color="${_c_cyan}"
        local cmd_color="${_c_green}"
        if [[ "${dangers[$i]}" == "1" ]]; then
            num_color="${_c_yellow}"
            cmd_color="${_c_yellow}"
        fi
        print "  ${_c_purple}│${_c_reset} ${num_color}[${i}]${_c_reset} ${_c_bold}${summaries[$i]}${_c_reset}"
        print "  ${_c_purple}│${_c_reset}     ${cmd_color}${commands[$i]}${_c_reset}"
        if [[ -n "${whys[$i]}" ]]; then
            print "  ${_c_purple}│${_c_reset}     ${_c_dim}${whys[$i]}${_c_reset}"
        fi
        if [[ $i -lt ${#commands[@]} ]]; then
            print "  ${_c_purple}│${_c_reset}"
        fi
    done
    if [[ ${#commands[@]} -gt 0 ]]; then
        local has_danger=0
        for d in "${dangers[@]}"; do [[ "$d" == "1" ]] && has_danger=1; done
        if [[ $has_danger -eq 1 ]]; then
            print "  ${_c_purple}│${_c_reset}"
            print "  ${_c_purple}│${_c_reset} ${_c_yellow}⚠ 包含危险命令，请仔细检查后再执行${_c_reset}"
        fi
    fi
    print "  ${_c_purple}╰──────────────────── 按数字键选择，其他键取消 ─╯${_c_reset}"
    print ""

    # Wait for single keypress
    local choice
    read -k 1 choice

    # Validate choice
    if [[ "$choice" =~ ^[1-9]$ ]] && (( choice <= ${#commands[@]} )); then
        BUFFER="${commands[$choice]}"
        CURSOR=${#BUFFER}
        print "\r\e[2K  ${_c_purple}✓${_c_reset} 已选择 ${_c_cyan}[${choice}]${_c_reset}\n"
    else
        BUFFER=""
        print "\r\e[2K  ${_c_grey}已取消${_c_reset}\n"
    fi
}

# ── Widget ────────────────────────────────────────────────────────────
_ai_shell_accept_line() {
    if [[ -n "$BUFFER" && "${BUFFER[1]}" == '#' && "$BUFFER" != *$'\n'* ]]; then
        local query="${BUFFER:1}"
        query="${query# }"

        if [[ -n "$query" ]]; then
            if [[ -z "$AI_SHELL_API_KEY" || -z "$AI_SHELL_MODEL" || -z "$AI_SHELL_BASE_URL" ]]; then
                print "\n  ${_c_purple}╭─ AI Shell${_c_reset}  ${_c_red}未配置${_c_reset}"
                print "  ${_c_purple}╰─${_c_reset} ${_c_grey}编辑 ~/.config/ai-shell/config${_c_reset}\n"
                zle reset-prompt
                return
            fi

            print -s -- "${BUFFER}"
            BUFFER=""
            zle -R ""

            _ai_shell_generate "$query"
            zle reset-prompt
            return
        fi
    fi

    zle .accept-line
}

# ── Registration ──────────────────────────────────────────────────────
_ai_shell_register() {
    zle -N accept-line _ai_shell_accept_line
    precmd_functions=("${precmd_functions[@]:#_ai_shell_register}")
}
precmd_functions+=(_ai_shell_register)
