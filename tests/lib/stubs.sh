# Fake commands for the tests: run a script with PATH="<dir>:$PATH" so that it calls these instead.
#
#   stub_path <dir> [docker] [getent] [powershell.exe]   writes the named fakes into <dir>:
#     docker           appends its arguments to $STUB_LOG (one line per call), prints nothing, exits 0
#     getent           answers $STUB_ADDRESS in the layout of `getent ahostsv4 <name>`
#     powershell.exe   answers $STUB_ADDRESS as [System.Net.Dns]::GetHostAddresses does, with the
#                      \r of a Windows console

stub_path() {
  local dir=$1 name
  shift
  mkdir -p "$dir"
  for name in "$@"; do
    case "$name" in
      docker)
        cat > "$dir/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >> "${STUB_LOG:?}"
EOF
        ;;
      getent)
        cat > "$dir/getent" <<'EOF'
#!/usr/bin/env bash
name=${!#}
printf '%-15s STREAM %s\n%-15s DGRAM  \n%-15s RAW    \n' "${STUB_ADDRESS:?}" "$name" "$STUB_ADDRESS" "$STUB_ADDRESS"
EOF
        ;;
      powershell.exe)
        cat > "$dir/powershell.exe" <<'EOF'
#!/usr/bin/env bash
printf '%s\r\n' "${STUB_ADDRESS:?}"
EOF
        ;;
      *)
        echo "stub_path: no stub for $name" >&2
        return 1
        ;;
    esac
    chmod +x "$dir/$name"
  done
}
