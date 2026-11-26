# Read-only diagnostics. Do not source the user's zsh startup files or run
# installed third-party tools here: either can trigger writes or auto-updates.
doctor_ok() { printf 'OK    %s\n' "$*"; }
doctor_info() { printf 'INFO  %s\n' "$*"; }
doctor_issue() {
  printf 'CHECK %s\n' "$*"
  DOCTOR_ISSUES=$((DOCTOR_ISSUES + 1))
}

doctor_file() {
  local name=$1 path=$2 test_flag=$3
  if { [[ $test_flag == executable && -f $path && -x $path ]] ||
       [[ $test_flag == readable && -f $path && -r $path ]]; }; then
    doctor_ok "$name: $path"
  else
    doctor_issue "$name: expected $path"
  fi
}

doctor_shell() {
  local shell rc=${ZDOTDIR:-$HOME}/.zshrc managed=$HOME/.config/mac-up/zshrc.zsh
  if shell=$(read_login_shell 2>/dev/null); then
    if [[ $shell == 'UserShell: /bin/zsh' ]]; then
      doctor_ok 'Login shell: /bin/zsh'
    else
      doctor_issue "Login shell: ${shell#UserShell: } (expected /bin/zsh)"
    fi
  else
    doctor_issue 'Could not read the account’s login shell'
  fi
  if [[ -f $rc ]] && grep -Fqx -- "$ZSH_LOADER" "$rc" &&
     cmp -s "$ROOT/config/zshrc.zsh" "$managed"; then
    doctor_ok 'Managed zsh config: loader and config match mac-up'
  else
    doctor_issue 'Managed zsh config: loader or config missing or different (standalone zsh settings may still work)'
  fi
}

doctor_tools() {
  local bin=$HOME/.local/bin selected tool
  if selected=$(/usr/bin/xcode-select -p 2>/dev/null) && [[ -d $selected ]]; then
    doctor_ok "Apple developer tools selected: $selected"
  else
    doctor_issue 'Apple developer tools are not selected; see xcode-select --install'
  fi
  doctor_file nvm "${NVM_DIR:-$HOME/.nvm}/nvm.sh" readable
  doctor_file 'zsh syntax highlighting' "$HOME/.local/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" readable
  for tool in fx uv uvx rg jq fzf gh; do
    doctor_file "$tool" "$bin/$tool" executable
  done
}

doctor_app() {
  local name=$1 app version
  for app in "/Applications/$name.app" "$HOME/Applications/$name.app"; do
    if version=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist" 2>/dev/null); then
      doctor_ok "$name $version: $app"
      return
    fi
  done
  doctor_issue "$name: no readable app bundle in /Applications or ~/Applications"
}

doctor_input() {
  local key type expected actual keys
  while read -r key type expected; do
    if actual=$(/usr/bin/defaults read -g "$key" 2>/dev/null); then
      if [[ $actual == "$expected" ]] || { [[ $type == float ]] && [[ $actual =~ ^${expected}\.0+$ ]]; }; then
        doctor_ok "$key: $actual"
      else
        doctor_issue "$key: $actual (expected $expected)"
      fi
    else
      doctor_issue "$key: not explicitly set (expected $expected)"
    fi
  done < <(input_preferences_table)

  if ! keys=$(detected_keyboard_keys 2>/dev/null) || [[ -z $keys ]]; then
    doctor_info 'Caps Lock: no keyboard IDs detected; check Modifier Keys in System Settings'
    return
  fi
  while IFS= read -r key; do
    if /usr/bin/defaults -currentHost read -g "$key" 2>/dev/null | caps_is_control; then
      doctor_ok "Caps Lock → Control saved for keyboard ID ${key##*.}"
    else
      doctor_issue "Caps Lock → Control not found for HID keyboard interface ${key##*.} (may be a peripheral)"
    fi
  done <<< "$keys"
}

doctor_rectangle() {
  local domain=$1 line
  local -a mismatches=()
  while IFS= read -r line; do
    [[ -n $line ]] && mismatches+=("$line")
  done < <(rectangle_mismatches "$domain")
  if (( ${#mismatches[@]} )); then
    doctor_issue "Rectangle saved shortcuts or preferences differ: ${mismatches[*]}"
  else
    doctor_ok 'Rectangle saved shortcuts and preferences match mac-up'
  fi
}

run_doctor() {
  local DOCTOR_ISSUES=0
  printf 'mac-up doctor (local checks only)\n\n'
  if (( MACOS_MAJOR < 14 )); then
    doctor_issue "macOS $MACOS_VERSION (mac-up requires 14 or newer)"
  else
    doctor_ok "macOS $MACOS_VERSION ($(uname -m))"
  fi
  doctor_shell
  doctor_tools
  doctor_app Ghostty
  doctor_app Rectangle
  doctor_app 'Google Chrome'
  doctor_app Tailscale
  doctor_rectangle com.knollsoft.Rectangle
  doctor_input
  printf '\n%d item(s) to review. No changes made.\n' "$DOCTOR_ISSUES"
  (( DOCTOR_ISSUES == 0 ))
}
