# Command-line logs for the tests: run a script with PATH="<dir>:$PATH" (or JAVA_HOME=<dir>) so that
# each command it calls writes its full command line to $ARGV_LOG, then runs the real one.
#
#   argv_log_path <dir> <command>…   writes into <dir>, for each named command, a wrapper that appends
#                                    "<command> <arguments…>" to $ARGV_LOG (one line per call) and
#                                    execs the real command, found with `command -v` before PATH changes
#   argv_log_java_home <dir>         makes <dir> a JAVA_HOME whose bin/keytool is such a wrapper of
#                                    $JAVA_HOME/bin/keytool (the real JDK's)
#
# A wrapper runs under this shell's bash ($BASH, an absolute path), so that the wrapper of bash doesn't
# run itself, and logs with printf, a builtin: logging puts nothing more on a command line.

argv_log_wrapper() { # <wrapper> <name> <real command>
  cat > "$1" <<EOF
#!$BASH
{ printf '%s' $(printf '%q' "$2"); printf ' %s' "\$@"; printf '\n'; } >> "\${ARGV_LOG:?}"
exec $(printf '%q' "$3") "\$@"
EOF
  chmod +x "$1"
}

argv_log_path() {
  local dir=$1 name real
  shift
  mkdir -p "$dir"
  for name in "$@"; do
    real=$(command -v "$name") || { echo "argv_log_path: no $name on PATH" >&2; return 1; }
    if [ "$real" = "$dir/$name" ]; then
      echo "argv_log_path: $dir is already on PATH: $name would run itself" >&2
      return 1
    fi
    argv_log_wrapper "$dir/$name" "$name" "$real"
  done
}

argv_log_java_home() {
  local dir=$1
  if [ -z "${JAVA_HOME:-}" ] || [ ! -x "$JAVA_HOME/bin/keytool" ]; then
    echo "argv_log_java_home: no bin/keytool in JAVA_HOME (${JAVA_HOME:-unset})" >&2
    return 1
  fi
  mkdir -p "$dir/bin"
  argv_log_wrapper "$dir/bin/keytool" keytool "$JAVA_HOME/bin/keytool"
}
