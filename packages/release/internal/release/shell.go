package release

import (
	"io"
	"strings"
)

const shellPrelude = `
log() { echo "[release] $*" >&2; }
version_meta_get() {
  local key="${1-}"
  local line
  while IFS= read -r line; do
    [[ $line == "$key="* ]] && printf '%s\n' "${line#*=}" && return 0
  done < <(tail -n +4 "$ROOT_DIR/VERSION" 2>/dev/null || true)
  return 1
}
version_meta_set() {
  local key="${1-}"
  local value="${2-}"
  local tmp
  tmp="$(mktemp)"
  awk -v key="$key" -v value="$value" '
    NR <= 3 { print; next }
    $0 ~ ("^" key "=") { print key "=" value; updated=1; next }
    { print }
    END { if (!updated) print key "=" value }
  ' "$ROOT_DIR/VERSION" >"$tmp"
  mv "$tmp" "$ROOT_DIR/VERSION"
  export_version_meta_env
}
version_meta_unset() {
  local key="${1-}"
  local tmp
  tmp="$(mktemp)"
  awk -v key="$key" '
    NR <= 3 { print; next }
    $0 ~ ("^" key "=") { next }
    { print }
  ' "$ROOT_DIR/VERSION" >"$tmp"
  mv "$tmp" "$ROOT_DIR/VERSION"
  export_version_meta_env
}
export_version_meta_env() {
  local line key value env_key
  while IFS= read -r line; do
    [[ $line == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    env_key="$(printf '%s' "$key" | tr -c '[:alnum:]' '_' | tr '[:lower:]' '[:upper:]')"
    export "VERSION_META_${env_key}=$value"
  done < <(tail -n +4 "$ROOT_DIR/VERSION" 2>/dev/null || true)
}
export_version_meta_env
`

func (r *Runner) runShell(rootDir string, versionFile *VersionFile, version Version, script string, stdout io.Writer, stderr io.Writer) error {
	if strings.TrimSpace(script) == "" {
		return nil
	}

	env := r.shellEnv(rootDir, versionFile, version)
	_, err := runCommand(rootDir, env, stdout, stderr, "bash", "-euo", "pipefail", "-c", shellPrelude+"\n"+script)
	return err
}

func (r *Runner) shellEnv(rootDir string, versionFile *VersionFile, version Version) []string {
	envMap := buildReleaseEnv(rootDir, versionFile, version, r.Config.Env)
	env := make([]string, 0, len(envMap))
	for key, value := range envMap {
		env = append(env, key+"="+value)
	}
	return env
}

func sanitizeMetaEnvName(key string) string {
	var b strings.Builder
	b.WriteString("VERSION_META_")
	for _, r := range key {
		switch {
		case r >= 'a' && r <= 'z':
			b.WriteRune(r - 32)
		case r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
			b.WriteRune(r)
		default:
			b.WriteByte('_')
		}
	}
	return b.String()
}
