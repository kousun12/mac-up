# Sourced by bootstrap.sh (macOS stock Bash).
ZSH_LOADER='[[ ! -r "$HOME/.config/mac-up/zshrc.zsh" ]] || source "$HOME/.config/mac-up/zshrc.zsh"'

read_login_shell() {
  /usr/bin/dscl . -read "/Users/$(/usr/bin/id -un)" UserShell
}

login_shell() {
  local current
  current=$(read_login_shell)
  if [[ $current != 'UserShell: /bin/zsh' ]]; then
    /usr/bin/chsh -s /bin/zsh
  fi
}

install_zsh_config() {
  local zdotdir=${ZDOTDIR:-$HOME} rc managed aliases=$HOME/.bash_aliases
  rc=$zdotdir/.zshrc
  managed=$HOME/.config/mac-up/zshrc.zsh
  mkdir -p "$zdotdir" "${managed%/*}"
  if [[ ! -e $aliases && ! -L $aliases ]]; then
    /bin/cp -n "$ROOT/config/bash_aliases" "$aliases"
  fi
  if [[ ! -e $managed ]] || ! cmp -s "$ROOT/config/zshrc.zsh" "$managed"; then
    install -m 644 "$ROOT/config/zshrc.zsh" "$managed"
  fi
  if [[ -f $rc ]] && grep -Fqx -- "$ZSH_LOADER" "$rc"; then
    return
  fi
  if [[ -e $rc || -L $rc ]]; then
    [[ -f $rc ]] || { warn "Not a regular file: $rc"; return 1; }
    local backup
    backup=$(mktemp "$rc.mac-up-backup.XXXXXX")
    cp -p "$rc" "$backup"
    printf 'Backed up zsh config to %s\n' "$backup"
  fi
  printf '\n# mac-up\n%s\n' "$ZSH_LOADER" >> "$rc"
}

input_preferences_table() {
  printf '%s\n' 'KeyRepeat int 2' 'InitialKeyRepeat int 15' \
    'com.apple.mouse.scaling float 2' 'com.apple.trackpad.scaling float 3'
}

input_preferences() {
  local key type value
  while read -r key type value; do
    /usr/bin/defaults write -g "$key" "-$type" "$value"
  done < <(input_preferences_table)
}

keyboard_keys() {
  local vendor product
  # hidutil reports both services and devices as hex vendor/product pairs.
  awk '$1 ~ /^0x[[:xdigit:]]+$/ && $2 ~ /^0x[[:xdigit:]]+$/ && $4 == 1 && $5 == 6 {print $1, $2}' |
    while read -r vendor product; do
      # The Bluetooth Logitech MX Master 3 advertises a keyboard interface.
      if (( vendor == 0x046d && product == 0xb023 )); then
        continue
      fi
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

detected_keyboard_keys() {
  /usr/bin/hidutil list --matching '{"PrimaryUsagePage":1,"PrimaryUsage":6}' | keyboard_keys
}

configure_caps_lock() {
  local keys key existing
  local mapping='<dict><key>HIDKeyboardModifierMappingSrc</key><integer>30064771129</integer><key>HIDKeyboardModifierMappingDst</key><integer>30064771300</integer></dict>'
  if ! keys=$(detected_keyboard_keys) || [[ -z $keys ]]; then
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

enable_rectangle_login() {
  # Rectangle reads this preference on startup and registers its own login item.
  /usr/bin/defaults write "$1" launchOnLogin -bool true
}

configure_rectangle() {
  local domain=com.knollsoft.Rectangle app=/Applications/Rectangle.app
  enable_rectangle_login "$domain"
  if /usr/bin/pgrep -u "$(/usr/bin/id -u)" -x Rectangle >/dev/null; then
    warn 'Rectangle is running. Quit it and rerun mac-up to apply shortcuts and register it at login.'
    return
  fi
  apply_rectangle_shortcuts "$domain"
  if [[ ! -f $app/Contents/Info.plist ]]; then
    app=$HOME/Applications/Rectangle.app
  fi
  if ! /usr/bin/open -g "$app"; then
    warn 'Could not start Rectangle. Open it manually to register it at login.'
  fi
}

configure_always_on() {
  local capabilities
  local -a settings=(sleep 0 displaysleep 10)
  if capabilities=$(/usr/bin/pmset -g cap) &&
     printf '%s\n' "$capabilities" | grep -Eq '^[[:space:]]*autorestart[[:space:]]*$'; then
    settings+=(autorestart 1)
  fi
  printf 'Disabling idle system sleep and setting display sleep to 10 minutes on AC power.\n'
  if ! /usr/bin/sudo /usr/bin/pmset -c "${settings[@]}"; then
    warn 'Could not apply always-on power settings.'
    return 1
  fi
  printf 'Disabling automatic logout without changing screen lock settings.\n'
  if ! /usr/bin/sudo /usr/bin/defaults write /Library/Preferences/.GlobalPreferences \
    com.apple.autologout.AutoLogOutDelay -int 0; then
    warn 'Could not disable automatic logout.'
    return 1
  fi
}

always_on_sharing_instructions() {
  printf '\n%s\n' 'Finish remote access on this Mac in System Settings > General > Sharing:' \
    '  Turn on Remote Login and Screen Sharing. For each, choose “Only these users” and add your Mac account.' \
    '  Leave full disk access for remote users and the separate VNC password option off unless needed.' \
    '  Screen Sharing and Remote Management cannot both be on; leave managed Macs to their administrator.' \
    '  Connect over Tailscale using the Mac’s MagicDNS name or Tailscale IP.' \
    '  For example: ssh youruser@office-mac or, from a Mac, open vnc://office-mac.' \
    '  Keep the Tailscale user session signed in; test both connections before leaving the Mac unattended.'
}
