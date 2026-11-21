#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT/lib/install.sh"
source "$ROOT/lib/settings.sh"
source "$ROOT/lib/doctor.sh"
warn() { printf 'Warning: %s\n' "$*" >&2; }

for file in "$ROOT/bootstrap.sh" "$ROOT"/lib/*.sh "$ROOT/tests/smoke.sh"; do
  /bin/bash -n "$file"
done
/bin/zsh -n "$ROOT/config/zshrc.zsh"

scratch=$(mktemp -d "${TMPDIR:-/tmp}/mac-up-test.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
export HOME="$scratch/home with spaces"
unset NVM_DIR ZDOTDIR
mkdir -p "$HOME"
/bin/bash "$ROOT/bootstrap.sh" --dry-run | grep -F 'Command Line Tools' >/dev/null
[[ -z $(/bin/ls -A "$HOME") ]]
plan=$(/bin/bash "$ROOT/bootstrap.sh" --dry-run --skip-clt)
[[ $plan != *'Command Line Tools'* && $plan == *'Rectangle'* && $plan == *'rg, jq, fzf, gh'* &&
   $plan == *'GitHub HTTPS credential helper'* ]]
rc=0
report=$(/bin/bash "$ROOT/bootstrap.sh" --doctor) || rc=$?
[[ $rc == 1 && $report == *'CHECK Managed zsh config:'* && $report == *'CHECK fx:'* &&
   $report == *'CHECK rg:'* && $report == *'CHECK jq:'* && $report == *'CHECK fzf:'* && $report == *'CHECK gh:'* &&
   $report == *'No changes made.'* ]]
[[ -z $(/bin/ls -A "$HOME") ]]
rc=0
/bin/bash "$ROOT/bootstrap.sh" --doctor --dry-run >/dev/null 2>&1 || rc=$?
[[ $rc == 64 ]]

# Exercise the verified binary installer without a network request.
(
  mkdir -p "$scratch/bin"
  printf '#!/bin/sh\nprintf "fixture\\n"\n' > "$scratch/asset"
  sha=$(/usr/bin/shasum -a 256 < "$scratch/asset")
  sha=${sha%% *}
  download() { cp "$scratch/asset" "$2"; }
  install_release_binary "$scratch/bin/tool" fixture "$sha"
  [[ $("$scratch/bin/tool") == fixture ]]
  download() { printf 'Reinstall tried to download an existing tool\n' >&2; exit 1; }
  install_release_binary "$scratch/bin/tool" fixture "$sha"
  download() { printf 'corrupted\n' > "$2"; }
  rc=0
  install_release_binary "$scratch/bin/bad" fixture "$sha" 2> "$scratch/checksum.log" || rc=$?
  [[ $rc == 1 && ! -e $scratch/bin/bad ]]
  grep -Fq 'Checksum verification failed' "$scratch/checksum.log"
)

printf '# Existing config\nexport MAC_UP_TEST=untouched\n' > "$HOME/.zshrc"
cp "$HOME/.zshrc" "$scratch/original"
install_zsh_config
cmp "$ROOT/config/bash_aliases" "$HOME/.bash_aliases"
printf '\n# user-owned aliases\n' >> "$HOME/.bash_aliases"
cp "$HOME/.bash_aliases" "$scratch/custom-aliases"
install_zsh_config
cmp "$scratch/custom-aliases" "$HOME/.bash_aliases"
backups=("$HOME/.zshrc.mac-up-backup."*)
[[ ${#backups[@]} == 1 ]]
cmp "${backups[0]}" "$scratch/original"
[[ $(grep -Fc '# mac-up' "$HOME/.zshrc") == 1 ]]
PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/zsh -ic '
  set -e
  [[ $MAC_UP_TEST == untouched && $path[1] == "$HOME/.local/bin" ]]
  [[ $aliases[gst] == "git status" && $aliases[gd] == "git diff" && $aliases[glog] == "git log --oneline --pretty=format:"* ]]
  (( $+functions[gcm] && $+functions[ggpush] ))
  [[ $HISTFILE == "$HOME/.zsh_history" && $HISTSIZE == 300000 && $SAVEHIST == 250000 ]]
  for map in emacs viins; do
    [[ $(bindkey -M "$map" "^R") == *" history-incremental-search-backward" ]]
  done
  psvar[1]="(main)"
  rendered=$(print -P -- "$PROMPT")
  [[ $rendered == *"(main)"*" " && $rendered != *"% " && $rendered != *"# " ]]
'

mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/fzf" <<'EOF'
#!/bin/sh
[ "$1" = --zsh ] || exit 1
cat <<'ZSH'
### key-bindings.zsh ###
if [[ ${FZF_CTRL_T_COMMAND-x} == '' && ${FZF_ALT_C_COMMAND-x} == '' ]]; then
  fzf-history-widget() { :; }
  zle -N fzf-history-widget
  bindkey -M emacs '^R' fzf-history-widget
  bindkey -M viins '^R' fzf-history-widget
fi
### end: key-bindings.zsh ###
### completion.zsh ###
bindkey -M emacs '^I' fzf-history-widget
### end: completion.zsh ###
ZSH
EOF
chmod +x "$HOME/.local/bin/fzf"
pty_output=$(/usr/bin/script -q /dev/null /bin/zsh -ic '
  set -e
  for map in emacs viins; do
    [[ $(bindkey -M "$map" "^R") == *" fzf-history-widget" ]]
    [[ $(bindkey -M "$map" "^I") != *fzf* ]]
  done
  print "fzf history binding verified"
' </dev/null)
[[ $pty_output == *'fzf history binding verified'* ]]

# Test the HTTPS helper setup without contacting GitHub or writing Git config.
if /usr/bin/xcode-select -p >/dev/null 2>&1; then
  (
    export GH_SETUP_LOG="$scratch/gh-setup.log" GH_TEST_SIGNED=0
    cat > "$HOME/.local/bin/gh" <<'EOF'
#!/bin/sh
case "$*" in
  'auth status --hostname github.com') [ "$GH_TEST_SIGNED" = 1 ] ;;
  'auth setup-git --hostname github.com') printf '%s\n' "$*" >> "$GH_SETUP_LOG" ;;
  *) exit 64 ;;
esac
EOF
    chmod +x "$HOME/.local/bin/gh"
    instructions=$(configure_github_credentials)
    [[ $instructions == *'gh auth login --hostname github.com --git-protocol https'* && ! -e $GH_SETUP_LOG ]]
    GH_TEST_SIGNED=1
    configure_github_credentials
    grep -Fxq 'auth setup-git --hostname github.com' "$GH_SETUP_LOG"
  )
fi

# Switch branches only in a disposable repo; intercept ggpush before any push.
/bin/bash -n "$HOME/.bash_aliases"
if /usr/bin/xcode-select -p >/dev/null 2>&1; then (
  source "$HOME/.bash_aliases"
  git init -q -b master "$scratch/git-repo"
  cd "$scratch/git-repo"
  git -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm 'Initial commit' --allow-empty
  git switch -qc feature
  gcm
  [[ $(git branch --show-current) == master ]]
  git branch release
  git update-ref refs/remotes/origin/release HEAD
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/release
  gcm
  [[ $(git branch --show-current) == release ]]

  mkdir "$scratch/git-stub"
  cat > "$scratch/git-stub/git" <<'EOF'
#!/bin/sh
if [ "$1" = push ]; then
  printf '%s\n' "$@"
else
  exec /usr/bin/git "$@"
fi
EOF
  chmod +x "$scratch/git-stub/git"
  [[ $(PATH="$scratch/git-stub:$PATH" ggpush --dry-run) == $'push\norigin\nrelease\n--dry-run' ]]
); fi

label=$(latest_clt_label <<'EOF'
* Label: Command Line Tools for Xcode-16.10
* Label: macOS Sequoia 15.7.2-24G325
* Label: Command Line Tools for Xcode-16.9
* Label: Command Line Tools for Xcode-17.0 beta
EOF
)
[[ $label == 'Command Line Tools for Xcode-16.10' ]]
[[ $(input_preferences_table) == *'InitialKeyRepeat int 15'* ]]

keys=$(keyboard_keys <<'EOF'
VendorID ProductID LocationID UsagePage Usage RegistryID Transport Class Product
0x19f5 0x1028 0x2120000 1 6 0x100001129 USB HID Keyboard
0x19f5 0x1028 0x2120000 1 6 0x100001129 USB HID Keyboard duplicate
0x46d 0xb023 0x36322a89 1 6 0x10000116b Bluetooth HID MX Master 3 keyboard interface
0x46d 0xb023 0x36322a89 1 2 0x10000116c Bluetooth HID MX Master 3 mouse interface
EOF
)
[[ $keys == com.apple.keyboard.modifiermapping.6645-4136-0 ]]
printf '{\n HIDKeyboardModifierMappingSrc = 30064771129;\n HIDKeyboardModifierMappingDst = 30064771300;\n}\n' | caps_is_control
if printf '{\n HIDKeyboardModifierMappingSrc = 30064771129;\n HIDKeyboardModifierMappingDst = 30064771301;\n}\n' | caps_is_control; then
  printf 'Incorrectly accepted Caps Lock to Shift\n' >&2
  exit 1
fi

domain="$scratch/rectangle"
/usr/bin/defaults write "$domain" unrelated -string preserved
apply_rectangle_shortcuts "$domain"
apply_rectangle_shortcuts "$domain"
[[ $(/usr/bin/defaults read "$domain" unrelated) == preserved ]]
[[ $(/usr/bin/defaults read "$domain" alternateDefaultShortcuts) == 1 ]]
[[ $(/usr/bin/defaults read "$domain" bottomLeft | tr -d '[:space:]') == '{}' ]]
[[ $(/usr/bin/defaults read "$domain" firstThird) == *'keyCode = 123;'* ]]
[[ $(/usr/bin/defaults read "$domain" lastTwoThirds) == *'keyCode = 124;'* ]]
[[ $(/usr/bin/defaults read "$domain" maximize) == *'modifierFlags = 786432;'* ]]
DOCTOR_ISSUES=0
doctor_rectangle "$domain"
[[ $DOCTOR_ISSUES == 0 ]]
/usr/bin/defaults write "$domain" maximize -dict
doctor_rectangle "$domain"
[[ $DOCTOR_ISSUES == 1 ]]
[[ $(/usr/bin/defaults read "$domain" maximize | tr -d '[:space:]') == '{}' ]]
printf 'mac-up smoke checks passed\n'
