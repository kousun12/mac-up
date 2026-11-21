# mac-up interactive shell settings.
typeset -U path
path=($HOME/.local/bin "${path[@]}")
export PATH

HISTFILE=${ZDOTDIR:-$HOME}/.zsh_history
HISTSIZE=50000
SAVEHIST=20000
setopt INC_APPEND_HISTORY HIST_IGNORE_DUPS HIST_FIND_NO_DUPS
bindkey -M emacs '^R' history-incremental-search-backward
bindkey -M viins '^R' history-incremental-search-backward

# Load only fzf's key bindings so it leaves existing Tab completion alone.
if [[ -t 0 && -o zle ]] && (( $+commands[fzf] )); then
  : ${FZF_CTRL_R_OPTS='--layout=reverse --border --prompt="History> "'}
  FZF_CTRL_T_COMMAND='' FZF_ALT_C_COMMAND='' source <(
    command fzf --zsh 2>/dev/null | /usr/bin/sed -n '/^### key-bindings\.zsh ###$/,/^### end: key-bindings\.zsh ###$/p'
  )
fi

PROMPT='%B%F{cyan}%~%f%b%1(V. %F{yellow}%1v%f.) %# '
if (( $+commands[git] )) &&
   { [[ $commands[git] != /usr/bin/git ]] || xcode-select -p >/dev/null 2>&1; }; then
  autoload -Uz add-zsh-hook vcs_info
  zstyle ':vcs_info:*' enable git
  zstyle ':vcs_info:git:*' formats '(%b)'
  zstyle ':vcs_info:git:*' actionformats '(%b|%a)'
  _zsh_prompt_git() {
    vcs_info
    psvar[1]=$vcs_info_msg_0_
  }
  add-zsh-hook precmd _zsh_prompt_git
fi

export NVM_DIR=${NVM_DIR:-$HOME/.nvm}
if (( ! $+functions[nvm] )) && [[ -r "$NVM_DIR/nvm.sh" ]]; then
  source "$NVM_DIR/nvm.sh"
fi

# Source highlighting after setting up bindings and widgets.
_mac_up_highlighter=$HOME/.local/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
if (( ! $+functions[_zsh_highlight] )) && [[ -r "$_mac_up_highlighter" ]]; then
  source "$_mac_up_highlighter"
fi
unset _mac_up_highlighter
