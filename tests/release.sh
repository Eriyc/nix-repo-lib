#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${REPO_LIB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RELEASE_TEMPLATE="$ROOT_DIR/packages/release/release.sh"

fail() {
	echo "[test] FAIL: $*" >&2
	exit 1
}

assert_eq() {
	local expected="$1"
	local actual="$2"
	local message="$3"
	if [[ "$expected" != "$actual" ]]; then
		fail "$message (expected '$expected', got '$actual')"
	fi
}

make_release_script() {
	local target="$1"
	sed \
		-e 's/__CHANNEL_LIST__/alpha beta rc internal/g' \
		-e 's/__RELEASE_STEPS__/:/' \
		-e 's/__POST_VERSION__/:/' \
		"$RELEASE_TEMPLATE" >"$target"
	chmod +x "$target"
}

setup_repo() {
	local repo_dir="$1"
	local remote_dir="$2"

	mkdir -p "$repo_dir"
	git -C "$repo_dir" init >/dev/null
	git -C "$repo_dir" config user.name "Release Test"
	git -C "$repo_dir" config user.email "release-test@example.com"

	cat >"$repo_dir/flake.nix" <<'EOF'
{
  description = "release test";
  outputs = { self }: { };
}
EOF

	printf '1.0.0\nstable\n0\n' >"$repo_dir/VERSION"
	git -C "$repo_dir" add -A
	git -C "$repo_dir" commit -m "init" >/dev/null

	git init --bare "$remote_dir" >/dev/null
	git -C "$repo_dir" remote add origin "$remote_dir"
	git -C "$repo_dir" push -u origin HEAD >/dev/null
}

version_from_file() {
	local repo_dir="$1"
	local base channel n
	base="$(sed -n '1p' "$repo_dir/VERSION" | tr -d '\r')"
	channel="$(sed -n '2p' "$repo_dir/VERSION" | tr -d '\r')"
	n="$(sed -n '3p' "$repo_dir/VERSION" | tr -d '\r')"

	if [[ -z "$channel" || "$channel" == "stable" ]]; then
		echo "$base"
	else
		echo "$base-$channel.$n"
	fi
}

run_case() {
	local case_name="$1"
	local command_args="$2"
	local expected_version="$3"

	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/repo"
	local remote_dir="$workdir/remote.git"

	setup_repo "$repo_dir" "$remote_dir"
	make_release_script "$repo_dir/release"

	mkdir -p "$repo_dir/bin"
	cat >"$repo_dir/bin/nix" <<'EOF'
#!/usr/bin/env bash
if [[ "${1-}" == "fmt" ]]; then
	exit 0
fi
echo "unexpected nix invocation: $*" >&2
exit 1
EOF
	chmod +x "$repo_dir/bin/nix"

	(
		cd "$repo_dir"
		PATH="$repo_dir/bin:$PATH" ./release $command_args >/dev/null
	)

	local got_version
	got_version="$(version_from_file "$repo_dir")"
	assert_eq "$expected_version" "$got_version" "$case_name: VERSION mismatch"

	if ! git -C "$repo_dir" tag --list | grep -qx "v$expected_version"; then
		fail "$case_name: expected tag v$expected_version was not created"
	fi

	rm -rf "$workdir"
	echo "[test] PASS: $case_name" >&2
}

run_case "channel-only from stable bumps patch" "beta" "1.0.1-beta.1"
run_case "explicit minor bump keeps requested bump" "minor beta" "1.1.0-beta.1"

echo "[test] All release tests passed" >&2
