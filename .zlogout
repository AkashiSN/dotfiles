# .zlogout

if [[ "$(uname -r)" == *microsoft* ]]; then
  gpg-agent-relay status > /dev/null && {
    gpg-agent-relay stop
  }
fi
