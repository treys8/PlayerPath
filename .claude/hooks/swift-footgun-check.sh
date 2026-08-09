#!/bin/bash
# PostToolUse hook: warn on PlayerPath-specific Swift footguns that have
# caused real production crashes. Warning-only (exit 2 feeds stderr back
# to Claude; the edit has already happened).

input=$(cat)
file_path=$(echo "$input" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)

[[ "$file_path" == *.swift ]] || exit 0
[[ -f "$file_path" ]] || exit 0

warnings=""

# Crashed build 169: a transform on a model keypath inside #Predicate traps
# fatally inside fetch (bypasses do/catch). Compare UUID-to-UUID instead.
#
# This check brace-matches the #Predicate closure and only looks INSIDE it.
# The previous file-level `grep #Predicate && grep .uuidString` fired whenever
# both strings appeared anywhere in the same file — it blocked every edit to
# GameDetailView.swift (cache-key interpolation) and GameService.swift
# (#Predicate only in a comment).
predicate_hits=$(python3 - "$file_path" <<'PY' 2>/dev/null
import re, sys

TRANSFORMS = ('.uuidString', '.lowercased()', '.uppercased()', '.trimmingCharacters')

try:
    src = open(sys.argv[1], encoding='utf-8', errors='ignore').read()
except OSError:
    sys.exit(0)

# Blank out string literal contents line-by-line so braces and interpolated
# `.uuidString` inside strings can't confuse the matcher. Line structure is
# preserved so reported line numbers stay accurate.
clean = '\n'.join(
    re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', line)
    for line in src.split('\n')
)

for m in re.finditer(r'#Predicate', clean):
    start = clean.find('{', m.end())
    if start < 0:
        continue
    depth = 0
    end = start
    while end < len(clean):
        c = clean[end]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                break
        end += 1
    body = clean[start:end + 1]
    found = [t for t in TRANSFORMS if t in body]
    if found:
        line = clean.count('\n', 0, start) + 1
        print(f"line {line}: {', '.join(found)}")
PY
)

if [[ -n "$predicate_hits" ]]; then
  warnings+="FOOTGUN: transform inside a #Predicate body — traps fatally at fetch, bypassing do/catch (crashed build 169). Compare UUID-to-UUID.\n"
  while IFS= read -r hit; do
    [[ -n "$hit" ]] && warnings+="  $hit\n"
  done <<< "$predicate_hits"
fi

# Project convention: silent save swallowing. Skip comment lines — the doc
# comment on ErrorHandlerService.saveContext quotes the banned form verbatim.
if grep -vE '^\s*(//|\*|/\*)' "$file_path" | grep -qE 'try\? +(self\.)?(context|modelContext)\.save\(\)'; then
  warnings+="CONVENTION: 'try? context.save()' found — use ErrorHandlerService.shared.saveContext(context, caller:) instead.\n"
fi

# iOS 26 async-let crash in Firebase HTTPSCallable. Ignore comment lines so a
# note explaining why the codebase avoids it doesn't trip the hook.
if grep -vE '^\s*(//|\*|/\*)' "$file_path" | grep -q "httpsCallable"; then
  warnings+="FOOTGUN: httpsCallable found — never use HTTPSCallable.call() (Firebase async-let crash on iOS 26). Call Cloud Functions via URLSession + Bearer token.\n"
fi

if [[ -n "$warnings" ]]; then
  printf "%b" "$warnings" >&2
  exit 2
fi
exit 0
