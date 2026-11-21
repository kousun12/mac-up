# Sourced by bootstrap.sh (macOS stock Bash).
login_shell() {
  local account current
  account=$(/usr/bin/id -un)
  current=$(/usr/bin/dscl . -read "/Users/$account" UserShell)
  if [[ $current != 'UserShell: /bin/zsh' ]]; then
    /usr/bin/chsh -s /bin/zsh
  fi
}

install_zsh_config() {
  local zdotdir=${ZDOTDIR:-$HOME} rc managed stanza
  rc=$zdotdir/.zshrc
  managed=$HOME/.config/mac-up/zshrc.zsh
  stanza='[[ ! -r "$HOME/.config/mac-up/zshrc.zsh" ]] || source "$HOME/.config/mac-up/zshrc.zsh"'
  mkdir -p "$zdotdir" "${managed%/*}"
  if [[ ! -e $managed ]] || ! cmp -s "$ROOT/config/zshrc.zsh" "$managed"; then
    install -m 644 "$ROOT/config/zshrc.zsh" "$managed"
  fi
  if [[ -f $rc ]] && grep -Fqx -- "$stanza" "$rc"; then
    return
  fi
  if [[ -e $rc || -L $rc ]]; then
    [[ -f $rc ]] || { warn "Not a regular file: $rc"; return 1; }
    local backup
    backup=$(mktemp "$rc.mac-up-backup.XXXXXX")
    cp -p "$rc" "$backup"
    printf 'Backed up zsh config to %s\n' "$backup"
  fi
  printf '\n# mac-up\n%s\n' "$stanza" >> "$rc"
}

input_preferences() {
  /usr/bin/defaults write -g KeyRepeat -int 2
  /usr/bin/defaults write -g InitialKeyRepeat -int 60
  /usr/bin/defaults write -g com.apple.mouse.scaling -float 2
  /usr/bin/defaults write -g com.apple.trackpad.scaling -float 3
}

keyboard_keys() {
  local vendor product
  # hidutil reports both services and devices as hex vendor/product pairs.
  awk '$1 ~ /^0x[[:xdigit:]]+$/ && $2 ~ /^0x[[:xdigit:]]+$/ && $4 == 1 && $5 == 6 {print $1, $2}' |
    while read -r vendor product; do
      printf 'com.apple.keyboard.modifiermapping.%d-%d-0\n' "$vendor" "$product"
    done | LC_ALL=C sort -u
}

caps_is_control() {
  awk -F '[ =;]+' '
    /\{/ {src = dst = ""}
    /HIDKeyboardModifierMappingSrc/ {src = $(NF-1)}
    /HIDKeyboardModifierMappingDst/ {dst = $(NF-1)}
    /\}/ && src == "30064771129" && (dst == "30064771300" || dst == "30064771296") {found = 1}
    END {exit !found}
  '
}

configure_caps_lock() {
  local devices keys key existing
  local mapping='<dict><key>HIDKeyboardModifierMappingSrc</key><integer>30064771129</integer><key>HIDKeyboardModifierMappingDst</key><integer>30064771300</integer></dict>'
  if ! devices=$(/usr/bin/hidutil list --matching '{"PrimaryUsagePage":1,"PrimaryUsage":6}') ||
     ! keys=$(printf '%s\n' "$devices" | keyboard_keys) || [[ -z $keys ]]; then
    warn 'No keyboard IDs found. Set Caps Lock to Control in System Settings > Keyboard > Keyboard Shortcuts > Modifier Keys.'
    return
  fi
  while IFS= read -r key; do
    if existing=$(/usr/bin/defaults -currentHost read -g "$key" 2>/dev/null); then
      if ! printf '%s\n' "$existing" | caps_is_control; then
        warn "Preserving existing modifier mappings for $key; set Caps Lock to Control in System Settings for that keyboard."
      fi
    else
      /usr/bin/defaults -currentHost write -g "$key" -array "$mapping"
    fi
  done <<< "$keys"
}

apply_rectangle_shortcuts() {
  local domain=$1 action code flags
  /usr/bin/defaults write "$domain" alternateDefaultShortcuts -bool true
  /usr/bin/defaults write "$domain" allowAnyShortcut -bool true
  /usr/bin/defaults write "$domain" subsequentExecutionMode -int 1
  while IFS=$'\t' read -r action code flags; do
    case $action in ''|\#*) continue ;; esac
    if [[ $code == - ]]; then
      /usr/bin/defaults write "$domain" "$action" -dict
    else
      /usr/bin/defaults write "$domain" "$action" -dict keyCode -int "$code" modifierFlags -int "$flags"
    fi
  done < "$ROOT/config/rectangle-shortcuts.tsv"
}

configure_rectangle() {
  if /usr/bin/pgrep -u "$(/usr/bin/id -u)" -x Rectangle >/dev/null; then
    warn 'Rectangle is running. Quit it and rerun mac-up to apply the saved shortcuts.'
    return
  fi
  apply_rectangle_shortcuts com.knollsoft.Rectangle
}
