#!/bin/bash
# Ставит notch-hook в ~/.local/bin и прописывает хуки Claude Code.
# Использование:
#   scripts/install-hooks.sh                 # в ~/.claude (или $CLAUDE_CONFIG_DIR)
#   scripts/install-hooks.sh DIR [DIR...]    # в несколько каталогов конфигурации (несколько аккаунтов)
#   scripts/install-hooks.sh --uninstall [DIR...]
# Перед изменением settings.json делает резервную копию settings.json.bak-<время>.
set -euo pipefail
cd "$(dirname "$0")/.."

uninstall=0
if [ "${1:-}" = "--uninstall" ]; then uninstall=1; shift; fi
dirs=("$@")
[ ${#dirs[@]} -eq 0 ] && dirs=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}")

hook="$HOME/.local/bin/notch-hook"
if [ $uninstall -eq 0 ]; then
    mkdir -p "$HOME/.local/bin"
    cp hooks/notch-hook "$hook"
    chmod +x "$hook"
    echo "✓ $hook"
fi

# Async-хук: Claude Code его не ждёт. SessionEnd — синхронно, иначе может не успеть при выходе.
filter='
  def h($async): [{hooks: [{type: "command", command: $cmd, timeout: 2} + (if $async then {async: true} else {} end)]}];
  def strip: with_entries(.value |= map(select((.hooks // []) | all(.command != $cmd)))) | with_entries(select(.value | length > 0));
  .hooks = ((.hooks // {}) | strip)
  | if $uninstall == 1 then (if (.hooks | length) == 0 then del(.hooks) else . end)
    else .hooks += {
      SessionStart: ((.hooks.SessionStart // []) + h(true)),
      UserPromptSubmit: ((.hooks.UserPromptSubmit // []) + h(true)),
      PermissionRequest: ((.hooks.PermissionRequest // []) + h(true)),
      PreToolUse: ((.hooks.PreToolUse // []) + [{matcher: "AskUserQuestion"} + h(true)[0]]),
      PostToolUse: ((.hooks.PostToolUse // []) + h(true)),
      PostToolUseFailure: ((.hooks.PostToolUseFailure // []) + h(true)),
      Notification: ((.hooks.Notification // []) + h(true)),
      Stop: ((.hooks.Stop // []) + h(true)),
      StopFailure: ((.hooks.StopFailure // []) + h(true)),
      SessionEnd: ((.hooks.SessionEnd // []) + h(false))
    } end'

for dir in "${dirs[@]}"; do
    settings="$dir/settings.json"
    mkdir -p "$dir"
    [ -f "$settings" ] || echo '{}' >"$settings"
    backup="$settings.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$settings" "$backup"
    tmp=$(mktemp)
    jq --arg cmd "$hook" --argjson uninstall "$uninstall" "$filter" "$settings" >"$tmp"
    mv "$tmp" "$settings"
    echo "✓ $settings (копия: $backup)"
done

if [ $uninstall -eq 1 ]; then
    echo "Хуки удалены. Скрипт $hook оставлен — удалите вручную, если не нужен."
fi
