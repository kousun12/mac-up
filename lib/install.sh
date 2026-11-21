# Sourced by bootstrap.sh (macOS stock Bash).
download() {
  /usr/bin/curl -q --proto '=https' --proto-redir '=https' --fail --silent --show-error \
    --location --retry 2 --connect-timeout 15 --max-time 600 -o "$2" "$1"
}

latest_clt_label() {
  # Pick the newest stable CLT label offered for this OS, never install unrelated updates.
  LC_ALL=C sed -nE 's/^[[:space:]*]*Label: (Command Line Tools for Xcode[- ]+[0-9]+(\.[0-9]+)*)[[:space:]]*$/\1/p' |
    LC_ALL=C sort -V | tail -n 1
}

configure_clt() {
  local updates label
  if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
    /usr/bin/xcode-select --install || warn 'Could not start Apple’s installer. Run xcode-select --install from a logged-in desktop.'
    CLT_PENDING=1
    return
  fi
  printf 'Checking Apple Software Update for Command Line Tools updates…\n'
  if ! updates=$(LC_ALL=C /usr/sbin/softwareupdate --list 2>&1); then
    warn "Could not check for Command Line Tools updates: $updates"
    CLT_PENDING=1
    return
  fi
  label=$(printf '%s\n' "$updates" | latest_clt_label)
  if [[ -n $label ]]; then
    if ! /usr/bin/sudo /usr/sbin/softwareupdate --install "$label"; then
      warn "Could not install $label. Check System Settings > General > Software Update."
      CLT_PENDING=1
    fi
  else
    printf 'No stable Command Line Tools update offered by Apple.\n'
  fi
}

install_archive() (
  local url=$1 name=$2 dest=$3 entry=$4 stage
  if [[ -r $dest/$entry ]]; then
    printf 'Keeping existing %s\n' "$dest"
    return
  fi
  [[ ! -e $dest && ! -L $dest ]] || { warn "Refusing to overwrite $dest"; return 1; }
  mkdir -p "${dest%/*}"
  # Stage on the destination filesystem so moving the directory is atomic.
  stage=$(mktemp -d "${dest%/*}/.mac-up.XXXXXXXX")
  trap 'rm -rf -- "$stage"' EXIT
  download "$url" "$stage/release.tar.gz"
  /usr/bin/tar -xzf "$stage/release.tar.gz" -C "$stage"
  [[ -r $stage/$name/$entry ]] || { warn "Missing $entry in $url"; return 1; }
  /bin/mv -n "$stage/$name" "$dest"
  [[ ! -e $stage/$name ]] || { warn "Destination appeared during install: $dest"; return 1; }
)

install_release_binary() (
  local dest=$1 url=$2 sha256=$3 archive_entry=${4:-} stage source
  if [[ -f $dest && -x $dest ]]; then
    printf 'Keeping existing %s\n' "$dest"
    return
  fi
  [[ ! -e $dest && ! -L $dest ]] || { warn "Refusing to overwrite $dest"; return 1; }
  stage=$(mktemp -d "${dest%/*}/.mac-up.XXXXXXXX")
  trap 'rm -rf -- "$stage"' EXIT
  printf 'Installing %s\n' "${dest##*/}"
  source=$stage/download
  download "$url" "$source"
  if ! printf '%s  %s\n' "$sha256" "$source" | /usr/bin/shasum -a 256 -c --status; then
    warn "Checksum verification failed for $url"
    return 1
  fi
  if [[ -n $archive_entry ]]; then
    /usr/bin/tar -xzf "$source" -C "$stage" "$archive_entry"
    source=$stage/$archive_entry
  fi
  /usr/bin/install -m 755 "$source" "$stage/executable"
  /bin/mv -n "$stage/executable" "$dest"
  [[ ! -e $stage/executable ]] || { warn "Destination appeared during install: $dest"; return 1; }
)

install_portable_tools() {
  local bin=$HOME/.local/bin rg_version=15.2.0 jq_version=1.8.2
  local rg_target rg_sha jq_target jq_sha rg_package
  case $(/usr/bin/uname -m) in
    arm64)
      rg_target=aarch64-apple-darwin
      rg_sha=3750b2e93f37e0c692657da574d7019a101c0084da05a790c83fd335bad973e4
      jq_target=arm64
      jq_sha=2d75340ba57a4b4b4c8708a21c2dc8e958a48aaa8bba13b27f77f6e4c0eca07e
      ;;
    x86_64)
      rg_target=x86_64-apple-darwin
      rg_sha=af7825fcc69a2afc7a7aea55fc9af90e26421d8f20fe59df32e233c0b8a231c1
      jq_target=amd64
      jq_sha=e94b266e3c26690550006abe63152b782280f4e14374accdf04cbde844f00bc0
      ;;
    *) warn 'No rg or jq binaries configured for this architecture'; return 1 ;;
  esac
  mkdir -p "$bin"
  rg_package=ripgrep-$rg_version-$rg_target
  install_release_binary "$bin/rg" "https://github.com/BurntSushi/ripgrep/releases/download/$rg_version/$rg_package.tar.gz" \
    "$rg_sha" "$rg_package/rg"
  install_release_binary "$bin/jq" "https://github.com/jqlang/jq/releases/download/jq-$jq_version/jq-macos-$jq_target" "$jq_sha"
}

install_fzf() {
  local bin=$HOME/.local/bin version=0.75.0 target sha
  case $(/usr/bin/uname -m) in
    arm64) target=arm64; sha=1e76698eb481436e42119bea6aa6e2bd9552ff090789d769c286e3c3a4e0ded6 ;;
    x86_64) target=amd64; sha=8fa67fa874468b8e73ecad2df82cc110026f45d10605128aaac6b191262d2844 ;;
    *) warn 'No fzf binary configured for this architecture'; return 1 ;;
  esac
  mkdir -p "$bin"
  install_release_binary "$bin/fzf" "https://github.com/junegunn/fzf/releases/download/v$version/fzf-$version-darwin_$target.tar.gz" "$sha" fzf
}

install_developer_tools() {
  local nvm_version=0.41.0 highlight_version=0.8.0
  install_archive "https://codeload.github.com/nvm-sh/nvm/tar.gz/refs/tags/v$nvm_version" \
    "nvm-$nvm_version" "${NVM_DIR:-$HOME/.nvm}" nvm.sh
  install_archive "https://codeload.github.com/zsh-users/zsh-syntax-highlighting/tar.gz/refs/tags/$highlight_version" \
    "zsh-syntax-highlighting-$highlight_version" "$HOME/.local/share/zsh/plugins/zsh-syntax-highlighting" zsh-syntax-highlighting.zsh

  local bin=$HOME/.local/bin
  mkdir -p "$bin"
  export PATH="$bin:$PATH"
  if [[ ! -x $bin/uv || ! -x $bin/uvx ]]; then
    download https://astral.sh/uv/install.sh "$WORK/uv.sh"
    UV_INSTALL_DIR="$bin" UV_NO_MODIFY_PATH=1 /bin/sh "$WORK/uv.sh"
  fi
  if [[ ! -x $bin/fx ]]; then
    download https://fx.sh/setup.sh "$WORK/fx.sh"
    FX_INSTALL_DIR="$bin" /bin/bash "$WORK/fx.sh"
  fi
  "$bin/uv" --version
  "$bin/uvx" --version
  "$bin/fx" --version
  /bin/zsh -fc 'source "$1/nvm.sh" --no-use; nvm --version' _ "${NVM_DIR:-$HOME/.nvm}"
}

install_app() (
  local name=$1 url=$2 ident=$3 team=$4 minimum=$5
  local dest=/Applications/$name mount source
  if [[ -f $dest/Contents/Info.plist || -f $HOME/Applications/$name/Contents/Info.plist ]]; then
    printf 'Keeping existing %s\n' "$name"
    return
  fi
  if (( MACOS_MAJOR < minimum )); then
    warn "$name requires macOS $minimum or newer; skipping it."
    return
  fi
  [[ ! -e $dest && ! -L $dest ]] || { warn "Refusing to overwrite $dest"; return 1; }
  printf 'Installing %s\n' "$name"
  download "$url" "$WORK/$ident.dmg"
  mount=$(mktemp -d "$WORK/mount.XXXXXXXX")
  /usr/bin/hdiutil attach "$WORK/$ident.dmg" -readonly -nobrowse -noautoopen -mountpoint "$mount" >/dev/null
  trap '/usr/bin/hdiutil detach "$mount" >/dev/null || warn "Could not detach $mount"' EXIT
  source=$mount/$name
  [[ -d $source ]] || { warn "Expected $name in the disk image"; return 1; }
  # Chrome ships Finder metadata on a helper; --strict rejects that metadata.
  /usr/bin/codesign --verify --deep \
    -R="anchor apple generic and identifier \"$ident\" and certificate leaf[subject.OU] = \"$team\"" "$source"
  /usr/sbin/spctl --assess --type execute "$source"
  [[ ! -e $dest && ! -L $dest ]] || { warn "Destination appeared during install: $dest"; return 1; }
  if [[ -w /Applications ]]; then
    /usr/bin/ditto "$source" "$dest"
  else
    /usr/bin/sudo /usr/bin/ditto "$source" "$dest"
  fi
)

install_apps() {
  install_app Ghostty.app https://release.files.ghostty.org/1.4.0/Ghostty.dmg com.mitchellh.ghostty 24VZTF6M5V 13
  install_app Rectangle.app https://download.rectangleapp.com/Rectangle2.0.5.dmg com.knollsoft.Rectangle XSYZ3E4B7D 14
  install_app 'Google Chrome.app' https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg com.google.Chrome EQHXZ8M8AV 13
}
