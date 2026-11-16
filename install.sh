#!/usr/bin/env bash
# Installs everything Spotter needs on this computer: macOS, or Debian / Ubuntu
# Linux. Run it from the spotter folder:   ./install.sh
#
# Safe to run again at any time (after an update, or if a step failed): it skips
# whatever is already installed.
set -Eeuo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
RUBY_VERSION=$(cat "$ROOT/web/.ruby-version")
PYTHON_VERSION=3.15
LOG="$ROOT/web/log/install.log"
mkdir -p "$ROOT/web/log"
NEEDS_RELOGIN=""

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
fail() {
  printf '\n\033[31mSetup stopped: %s\033[0m\n' "$*" >&2
  exit 1
}
trap 'fail "a step failed - the messages above say why. Fix it, then run ./install.sh again."' ERR

# A yes/no question; "no" when nobody is there to answer.
ask() {
  [ -t 0 ] || return 1
  local reply
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy] ]]
}

# --- Tools: Python, Ruby and the libraries they need --------------------------

install_mac_tools() {
  if ! xcode-select -p >/dev/null 2>&1; then
    step "Installing Apple's command line tools"
    xcode-select --install || true
    fail "finish the install in the window that just opened, then run ./install.sh again."
  fi

  load_brew
  if ! command -v brew >/dev/null; then
    step "Installing Homebrew (it asks for your Mac password)"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    load_brew
    command -v brew >/dev/null || fail "Homebrew didn't install. See https://brew.sh, then run ./install.sh again."
  fi

  local wanted=("python@$PYTHON_VERSION" rbenv ruby-build openssl@3 libyaml) missing=() f
  for f in "${wanted[@]}"; do brew list --versions "$f" >/dev/null || missing+=("$f"); done
  if [ ${#missing[@]} -gt 0 ]; then
    step "Installing ${missing[*]} (Homebrew)"
    brew install "${missing[@]}"
  fi
  # ruby-build must know this Ruby version; an older one learns it by upgrading.
  rbenv install --list-all 2>/dev/null | grep -qx "$RUBY_VERSION" || brew upgrade ruby-build
  PYTHON="$(brew --prefix "python@$PYTHON_VERSION")/bin/python$PYTHON_VERSION"
}

load_brew() {
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$b" ]; then eval "$("$b" shellenv)"; return; fi
  done
}

install_linux_tools() {
  command -v apt-get >/dev/null ||
    fail "this script knows Debian and Ubuntu (apt). On another Linux, install the libraries listed in docs/building-a-rig.md, then run it again."

  step "Installing system libraries (it asks for your password)"
  sudo apt-get update
  sudo apt-get install -y git curl build-essential xdg-utils avahi-daemon \
    libgl1 libglib2.0-0 libportaudio2 \
    libssl-dev libyaml-dev libffi-dev zlib1g-dev libreadline-dev libsqlite3-dev \
    libbz2-dev liblzma-dev libncurses-dev tk-dev

  step "Installing Python $PYTHON_VERSION (a few minutes the first time)"
  export PYENV_ROOT="$HOME/.pyenv"
  [ -d "$PYENV_ROOT" ] || git clone --depth 1 https://github.com/pyenv/pyenv.git "$PYENV_ROOT"
  git -C "$PYENV_ROOT" pull -q || true            # knows the newest Python versions
  export PATH="$PYENV_ROOT/bin:$PATH"
  local version
  version=$(pyenv latest -k "$PYTHON_VERSION")
  pyenv install -s "$version"
  PYTHON="$(pyenv prefix "$version")/bin/python"

  local rbenv_root="$HOME/.rbenv"
  [ -d "$rbenv_root" ] || git clone --depth 1 https://github.com/rbenv/rbenv.git "$rbenv_root"
  [ -d "$rbenv_root/plugins/ruby-build" ] ||
    git clone --depth 1 https://github.com/rbenv/ruby-build.git "$rbenv_root/plugins/ruby-build"
  git -C "$rbenv_root/plugins/ruby-build" pull -q || true   # knows the newest Ruby versions
  export PATH="$rbenv_root/bin:$PATH"

  # The camera and microphone belong to these groups.
  if ! id -nG "$USER" | grep -qw video || ! id -nG "$USER" | grep -qw audio; then
    step "Giving you access to the camera and microphone"
    sudo usermod -aG video,audio "$USER"
    NEEDS_RELOGIN=1
  fi
}

case "$(uname -s)" in
  Darwin) install_mac_tools ;;
  Linux) install_linux_tools ;;
  *) fail "Spotter runs on macOS or Linux." ;;
esac

step "Installing Ruby $RUBY_VERSION (5-10 minutes the first time)"
rbenv install -s "$RUBY_VERSION"
rbenv init >/dev/null 2>&1 || true   # new Terminal windows find this Ruby too (bin/rails ...)
eval "$(rbenv init - bash)"

# --- The engine (Python) --------------------------------------------------------

step "Setting up the engine"
cd "$ROOT/engine"
[ -x .venv/bin/python ] || "$PYTHON" -m venv .venv
.venv/bin/python -m pip install -q --disable-pip-version-check -r requirements.txt

step "Checking the engine's maths (no camera needed)"
if ! .venv/bin/python selftest.py >"$LOG" 2>&1; then
  tail -20 "$LOG"
  fail "the self-test failed (full output in web/log/install.log)."
fi
note "passed"

# --- The app (Ruby on Rails) ----------------------------------------------------

step "Setting up the app"
cd "$ROOT/web"
bundle install --quiet
bin/rails db:prepare
bin/rails tailwindcss:build >/dev/null 2>&1

# --- A phone or tablet as the range screen (optional) ---------------------------

if ask $'\nWill you use a phone or tablet as the range screen (Rig B)?'; then
  touch .env
  grep -v '^SPOTTER_BIND=' .env >.env.new || true
  echo "SPOTTER_BIND=0.0.0.0" >>.env.new
  mv .env.new .env
  bin/rails spotter:tls
  note "Done. To let the phone use its microphone, trust the certificate on it:"
  note "see \"Watching from another device\" in docs/building-a-rig.md."
fi

# --- A launcher -----------------------------------------------------------------

if [ "$(uname -s)" = Linux ]; then
  mkdir -p "$HOME/.local/share/applications"
  cat >"$HOME/.local/share/applications/spotter.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Spotter
Comment=Start Spotter and open it in the browser
Exec="$ROOT/start-spotter"
Terminal=true
Categories=Utility;
EOF
fi

step "Spotter is installed"
if [ "$(uname -s)" = Darwin ]; then
  note "To start it: double-click \"Start Spotter.command\" in the spotter folder."
  note "The first time, macOS asks to let Terminal use the camera and microphone:"
  note "allow both, then quit Terminal completely (Cmd+Q) and start Spotter again."
else
  note "To start it: \"Spotter\" in your applications menu, or ./start-spotter"
  [ -z "$NEEDS_RELOGIN" ] || note "First log out and back in, so the camera and microphone work."
fi
