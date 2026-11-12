#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

LABEL=local.focus
INSTALLED_APP="$HOME/Applications/Focus.app"
AGENT_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

usage() {
  echo "Usage: scripts/install.sh [--login | --uninstall]" >&2
  exit 2
}

MODE=install
case "${1:-}" in
  "") ;;
  --login) MODE=login ;;
  --uninstall) MODE=uninstall ;;
  *) usage ;;
esac
[ $# -le 1 ] || usage

if [ "$MODE" = uninstall ]; then
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$AGENT_PLIST"
  pkill -x Focus || true
  rm -rf "$INSTALLED_APP"
  echo "Uninstalled. Settings in ~/.config/status-widget and the Keychain item were kept."
  exit 0
fi

scripts/build.sh
pkill -x Focus || true
for _ in $(seq 1 50); do
  pgrep -x Focus >/dev/null || break
  sleep 0.1
done
mkdir -p "$HOME/Applications"
rm -rf "$INSTALLED_APP"
cp -R build/app.noindex/Focus.app "$INSTALLED_APP"
touch "$INSTALLED_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALLED_APP"
echo "Installed $INSTALLED_APP"

if [ "$MODE" = login ]; then
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$INSTALLED_APP/Contents/MacOS/Focus</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
PLIST
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  launchctl bootstrap "$DOMAIN" "$AGENT_PLIST"
  echo "Login item installed: $AGENT_PLIST"
else
  open "$INSTALLED_APP"
fi
