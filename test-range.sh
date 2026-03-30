#!/bin/bash
# Interactive tool: walk through each VOD and deny-list broken ones.
# Shows rkey to disambiguate duplicate titles.
# Outputs to public/denied-vods.json.

PDS="https://iameli.com"
REPO="did:plc:rbvrr34edl5ddpuwcubjiost"
COLLECTION="place.stream.video"

DENY_FILE="public/denied-vods.json"

# Load existing deny list
if [ -f "$DENY_FILE" ]; then
  EXISTING=$(cat "$DENY_FILE")
else
  EXISTING="[]"
fi

echo "Fetching VOD list..."

RECORDS=""
CURSOR=""
while true; do
  URL="${PDS}/xrpc/com.atproto.repo.listRecords?repo=${REPO}&collection=${COLLECTION}&limit=100"
  [ -n "$CURSOR" ] && URL="${URL}&cursor=${CURSOR}"
  PAGE=$(curl -s "$URL")
  RECORDS="${RECORDS}$(echo "$PAGE" | python3 -c "import sys,json; [print(json.dumps(r)) for r in json.load(sys.stdin).get('records',[])]")"$'\n'
  CURSOR=$(echo "$PAGE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cursor',''))")
  [ -z "$CURSOR" ] && break
done

TOTAL=$(echo "$RECORDS" | grep -c '{')
echo "Found $TOTAL VODs."
echo ""
echo "  y = deny    n = allow [default]    s = skip    q = quit"
echo ""

DENIED=()
while IFS= read -r uri; do
  [ -n "$uri" ] && DENIED+=("$uri")
done < <(echo "$EXISTING" | python3 -c "import sys,json; [print(u) for u in json.load(sys.stdin)]" 2>/dev/null)

COUNT=0
while IFS= read -r record; do
  [ -z "$record" ] && continue
  eval "$(echo "$record" | python3 -c "
import sys,json
r = json.load(sys.stdin)
uri = r['uri']
rkey = uri.split('/')[-1]
title = r['value'].get('title','untitled')
dur = round(r['value'].get('duration',0)/1e9)
# Shell-escape the title
import shlex
print(f'URI={shlex.quote(uri)}')
print(f'RKEY={shlex.quote(rkey)}')
print(f'TITLE={shlex.quote(title)}')
print(f'DURATION={dur}')
")"
  COUNT=$((COUNT + 1))

  ALREADY_DENIED=""
  for d in "${DENIED[@]}"; do
    [ "$d" = "$URI" ] && ALREADY_DENIED="yes" && break
  done

  TAG=""
  [ -n "$ALREADY_DENIED" ] && TAG=" \033[31m[DENIED]\033[0m"

  printf "[%d/%d]%b %s (%ss) \033[2m%s\033[0m\n" "$COUNT" "$TOTAL" "$TAG" "$TITLE" "$DURATION" "$RKEY"
  printf "  (y/n/s/q) [n]: "
  read -r ANSWER </dev/tty

  case "$ANSWER" in
    y|Y)
      if [ -z "$ALREADY_DENIED" ]; then DENIED+=("$URI"); fi
      echo "  → denied"
      ;;
    q|Q) echo "Quitting..."; break ;;
    s|S) echo "  → skipped" ;;
    *)
      if [ -n "$ALREADY_DENIED" ]; then
        NEW_DENIED=()
        for d in "${DENIED[@]}"; do [ "$d" != "$URI" ] && NEW_DENIED+=("$d"); done
        DENIED=("${NEW_DENIED[@]}")
        echo "  → allowed (removed from deny list)"
      else
        echo "  → allowed"
      fi
      ;;
  esac
done <<< "$RECORDS"

python3 -c "
import json
uris = '''$(printf '%s\n' "${DENIED[@]}")'''.strip().split('\n')
uris = [u for u in uris if u]
print(json.dumps(uris, indent=2))
" > "$DENY_FILE"

echo ""
echo "Saved ${#DENIED[@]} denied VODs to $DENY_FILE"
