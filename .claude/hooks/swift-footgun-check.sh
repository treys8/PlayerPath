#!/bin/bash
# PostToolUse hook: warn on PlayerPath-specific Swift footguns that have
# caused real production crashes. Warning-only (exit 2 feeds stderr back
# to Claude; the edit has already happened).

input=$(cat)
file_path=$(echo "$input" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)

[[ "$file_path" == *.swift ]] || exit 0
[[ -f "$file_path" ]] || exit 0

warnings=""

# Crashed build 169: any transform on a model keypath inside #Predicate traps
# fatally inside fetch (bypasses do/catch). Compare UUID-to-UUID instead.
if grep -q "#Predicate" "$file_path" && grep -q "\.uuidString" "$file_path"; then
  warnings+="FOOTGUN: file uses #Predicate and .uuidString — if .uuidString is inside the predicate this traps fatally at fetch (crashed build 169). Compare UUID-to-UUID.\n"
fi

# Project convention: silent save swallowing
if grep -qE 'try\? +(self\.)?(context|modelContext)\.save\(\)' "$file_path"; then
  warnings+="CONVENTION: 'try? context.save()' found — use ErrorHandlerService.shared.saveContext(context, caller:) instead.\n"
fi

# iOS 26 async-let crash in Firebase HTTPSCallable
if grep -q "httpsCallable" "$file_path"; then
  warnings+="FOOTGUN: httpsCallable found — never use HTTPSCallable.call() (Firebase async-let crash on iOS 26). Call Cloud Functions via URLSession + Bearer token.\n"
fi

if [[ -n "$warnings" ]]; then
  printf "%b" "$warnings" >&2
  exit 2
fi
exit 0
