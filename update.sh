#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")" || exit 1

export PATH="$PATH:$HOME/.dotnet/tools"
if ! command -v deepstrip >/dev/null 2>&1; then
  dotnet tool install --global DeepStrip
fi

BloonsTD6=$(< ../btd6.targets sed -En 's:.*>(.*)</BloonsTD6>.*:\1:p')
DLLS=$(< ../btd6.targets sed -En 's:.*Reference Include="\$\(Il2CppAssemblies\)\\(.*\.dll)".*:\1:p')

if [ -z "$BloonsTD6" ] || [ -z "$DLLS" ]; then
  echo "Missing game path or interop references in ../btd6.targets" >&2
  exit 1
fi

# This retained transitive dependency is not yet listed in btd6.targets.
if ! printf '%s\n' "$DLLS" | grep -Fxq 'Il2CppNinjaKiwi.LiNK.dll'; then
  DLLS="$DLLS"$'\nIl2CppNinjaKiwi.LiNK.dll'
fi

for dll in $DLLS; do
  if [ ! -f "$BloonsTD6/MelonLoader/Il2CppAssemblies/$dll" ]; then
    echo "Missing interop source: $dll" >&2
    exit 1
  fi
done

# Keep existing references intact if any stripping operation fails.
: "${TMP:?TMP must point to a temporary directory}"
STAGING=$(mktemp -d "${TMP//\\//}/btd6-ci-dependencies.XXXXXX")
trap 'rm -rf -- "$STAGING"' EXIT

for dll in $DLLS
do
  REAL_DLL="$BloonsTD6/MelonLoader/Il2CppAssemblies/$dll"
  STRIPPED_DLL="$STAGING/$dll"
  
  deepstrip "$REAL_DLL" "$STRIPPED_DLL" -v -i \
    "$BloonsTD6/MelonLoader/Il2CppAssemblies" "$BloonsTD6/MelonLoader/net6"
  if [ ! -s "$STRIPPED_DLL" ]; then
    echo "DeepStrip produced no output: $dll" >&2
    exit 1
  fi
  echo Deep stripped "$REAL_DLL to $STRIPPED_DLL"
done

for dll in $DLLS; do
  cp "$STAGING/$dll" "./$dll"
done

if [ -t 0 ]; then
  read -r -n 1 -p "Press Any Key to exit" || true
fi
