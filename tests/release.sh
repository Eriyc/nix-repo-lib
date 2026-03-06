#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${REPO_LIB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RELEASE_TEMPLATE="$ROOT_DIR/packages/release/release.sh"
CURRENT_LOG=""

fail() {
	echo "[test] FAIL: $*" >&2
	if [[ -n "$CURRENT_LOG" && -f "$CURRENT_LOG" ]]; then
		echo "[test] ---- captured output ----" >&2
		cat "$CURRENT_LOG" >&2
		echo "[test] -------------------------" >&2
	fi
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

assert_contains() {
	local needle="$1"
	local haystack_file="$2"
	local message="$3"
	if ! grep -Fq "$needle" "$haystack_file"; then
		fail "$message (missing '$needle')"
	fi
}

run_capture_ok() {
	local description="$1"
	shift
	if ! "$@" >>"$CURRENT_LOG" 2>&1; then
		fail "$description"
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
	run_capture_ok "setup_repo: git init failed" git -C "$repo_dir" init
	run_capture_ok "setup_repo: git config user.name failed" git -C "$repo_dir" config user.name "Release Test"
	run_capture_ok "setup_repo: git config user.email failed" git -C "$repo_dir" config user.email "release-test@example.com"

	cat >"$repo_dir/flake.nix" <<'EOF'
{
  description = "release test";
  outputs = { self }: { };
}
EOF

	printf '1.0.0\nstable\n0\n' >"$repo_dir/VERSION"
	run_capture_ok "setup_repo: git add failed" git -C "$repo_dir" add -A
	run_capture_ok "setup_repo: git commit failed" git -C "$repo_dir" commit -m "init"

	run_capture_ok "setup_repo: git init --bare failed" git init --bare "$remote_dir"
	run_capture_ok "setup_repo: git remote add failed" git -C "$repo_dir" remote add origin "$remote_dir"
	run_capture_ok "setup_repo: initial push failed" git -C "$repo_dir" push -u origin HEAD
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

prepare_case_repo() {
	local repo_dir="$1"
	local remote_dir="$2"

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
}

run_release() {
	local repo_dir="$1"
	shift
	(
		cd "$repo_dir"
		PATH="$repo_dir/bin:$PATH" ./release "$@"
	)
}

qc_version_cmp() {
	# Returns: 0 if equal, 1 if v1 > v2, 2 if v1 < v2
	local v1="$1" v2="$2"
	[[ $v1 == "$v2" ]] && return 0

	local base1="" pre1="" base2="" pre2=""
	if [[ $v1 =~ ^([0-9]+\.[0-9]+\.[0-9]+)-(.+)$ ]]; then
		base1="${BASH_REMATCH[1]}"
		pre1="${BASH_REMATCH[2]}"
	else
		base1="$v1"
	fi
	if [[ $v2 =~ ^([0-9]+\.[0-9]+\.[0-9]+)-(.+)$ ]]; then
		base2="${BASH_REMATCH[1]}"
		pre2="${BASH_REMATCH[2]}"
	else
		base2="$v2"
	fi

	if [[ $base1 != "$base2" ]]; then
		local highest_base
		highest_base=$(printf '%s\n%s\n' "$base1" "$base2" | sort -V | tail -n1)
		[[ $highest_base == "$base1" ]] && return 1 || return 2
	fi

	[[ -z $pre1 && -n $pre2 ]] && return 1
	[[ -n $pre1 && -z $pre2 ]] && return 2
	[[ -z $pre1 && -z $pre2 ]] && return 0

	local highest_pre
	highest_pre=$(printf '%s\n%s\n' "$pre1" "$pre2" | sort -V | tail -n1)
	[[ $highest_pre == "$pre1" ]] && return 1 || return 2
}

qc_parse_base_version() {
	local v="$1"
	if [[ ! $v =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
		return 1
	fi
	QC_MAJOR="${BASH_REMATCH[1]}"
	QC_MINOR="${BASH_REMATCH[2]}"
	QC_PATCH="${BASH_REMATCH[3]}"
	return 0
}

qc_parse_full_version() {
	local v="$1"
	QC_CHANNEL="stable"
	QC_PRERELEASE_NUM=""

	if [[ $v =~ ^([0-9]+\.[0-9]+\.[0-9]+)-([a-zA-Z]+)\.([0-9]+)$ ]]; then
		QC_BASE_VERSION="${BASH_REMATCH[1]}"
		QC_CHANNEL="${BASH_REMATCH[2]}"
		QC_PRERELEASE_NUM="${BASH_REMATCH[3]}"
	elif [[ $v =~ ^([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
		QC_BASE_VERSION="${BASH_REMATCH[1]}"
	else
		return 1
	fi

	qc_parse_base_version "$QC_BASE_VERSION"
}

qc_validate_channel() {
	local channel="$1"
	[[ $channel == "stable" || $channel == "alpha" || $channel == "beta" || $channel == "rc" || $channel == "internal" ]]
}

qc_compute_full_version() {
	if [[ $QC_CHANNEL == "stable" || -z $QC_CHANNEL ]]; then
		QC_FULL_VERSION="$QC_BASE_VERSION"
	else
		QC_FULL_VERSION="$QC_BASE_VERSION-$QC_CHANNEL.${QC_PRERELEASE_NUM:-1}"
	fi
}

qc_bump_base_version() {
	qc_parse_base_version "$QC_BASE_VERSION"
	case "$1" in
	major)
		QC_MAJOR=$((QC_MAJOR + 1))
		QC_MINOR=0
		QC_PATCH=0
		;;
	minor)
		QC_MINOR=$((QC_MINOR + 1))
		QC_PATCH=0
		;;
	patch)
		QC_PATCH=$((QC_PATCH + 1))
		;;
	esac
	QC_BASE_VERSION="$QC_MAJOR.$QC_MINOR.$QC_PATCH"
}

qc_oracle_init() {
	QC_STATE_BASE="1.0.0"
	QC_STATE_CHANNEL="stable"
	QC_STATE_PRE=""
}

qc_oracle_current_full() {
	QC_BASE_VERSION="$QC_STATE_BASE"
	QC_CHANNEL="$QC_STATE_CHANNEL"
	QC_PRERELEASE_NUM="$QC_STATE_PRE"
	qc_compute_full_version
	echo "$QC_FULL_VERSION"
}

qc_pick_channel() {
	local channels=(alpha beta rc internal)
	echo "${channels[RANDOM % ${#channels[@]}]}"
}

qc_build_random_command() {
	local current_full="$1"
	QC_CMD_ARGS=()

	local mode=$((RANDOM % 7))
	case "$mode" in
	0)
		QC_CMD_ARGS=(patch)
		;;
	1)
		local bumps=(major minor patch)
		QC_CMD_ARGS=("${bumps[RANDOM % ${#bumps[@]}]}")
		;;
	2)
		local bumps=(major minor patch)
		QC_CMD_ARGS=("${bumps[RANDOM % ${#bumps[@]}]}" "$(qc_pick_channel)")
		;;
	3)
		QC_CMD_ARGS=("$(qc_pick_channel)")
		;;
	4)
		if (( RANDOM % 2 == 0 )); then
			QC_CMD_ARGS=(stable)
		else
			QC_CMD_ARGS=(full)
		fi
		;;
	5)
		QC_CMD_ARGS=(set "$current_full")
		;;
	6)
		qc_parse_base_version "$QC_STATE_BASE"
		if (( RANDOM % 2 == 0 )); then
			QC_CMD_ARGS=(set "$((QC_MAJOR + 1)).0.0")
		else
			QC_CMD_ARGS=(set "$QC_STATE_BASE-$(qc_pick_channel).1")
		fi
		;;
	esac
}

qc_oracle_apply() {
	local current_full
	current_full="$(qc_oracle_current_full)"

	QC_EXPECT_SUCCESS=0
	QC_EXPECT_VERSION="$current_full"

	local action="${1-}"
	shift || true

	if [[ $action == "set" ]]; then
		local newv="${1-}"
		[[ -z $newv ]] && return 0
		qc_parse_full_version "$newv" || return 0
		qc_validate_channel "$QC_CHANNEL" || return 0
		if [[ $QC_STATE_CHANNEL != "stable" && $QC_CHANNEL == "stable" ]]; then
			return 0
		fi
		qc_compute_full_version
		local cmp_status=0
		qc_version_cmp "$QC_FULL_VERSION" "$current_full" || cmp_status=$?
		if [[ $cmp_status -eq 0 || $cmp_status -eq 2 ]]; then
			return 0
		fi

		QC_STATE_BASE="$QC_BASE_VERSION"
		QC_STATE_CHANNEL="$QC_CHANNEL"
		QC_STATE_PRE="$QC_PRERELEASE_NUM"
		QC_EXPECT_SUCCESS=1
		QC_EXPECT_VERSION="$QC_FULL_VERSION"
		return 0
	fi

	local part="" target_channel="" was_channel_only=0
	case "$action" in
	"")
		part="patch"
		;;
	major | minor | patch)
		part="$action"
		target_channel="${1-}"
		if [[ -n ${1-} ]]; then
			shift || true
			[[ -n ${1-} ]] && return 0
		fi
		;;
	stable | full)
		[[ -n ${1-} ]] && return 0
		target_channel="stable"
		;;
	alpha | beta | rc | internal)
		[[ -n ${1-} ]] && return 0
		target_channel="$action"
		was_channel_only=1
		;;
	*)
		return 0
		;;
	esac

	[[ -z $target_channel ]] && target_channel="$QC_STATE_CHANNEL"
	[[ $target_channel == "full" ]] && target_channel="stable"
	qc_validate_channel "$target_channel" || return 0
	if [[ $QC_STATE_CHANNEL != "stable" && $target_channel == "stable" && $action != "stable" && $action != "full" ]]; then
		return 0
	fi

	if [[ -z $part && $was_channel_only -eq 1 && $QC_STATE_CHANNEL == "stable" && $target_channel != "stable" ]]; then
		part="patch"
	fi

	QC_BASE_VERSION="$QC_STATE_BASE"
	QC_CHANNEL="$QC_STATE_CHANNEL"
	QC_PRERELEASE_NUM="$QC_STATE_PRE"

	local old_base="$QC_BASE_VERSION"
	local old_channel="$QC_CHANNEL"
	local old_pre="$QC_PRERELEASE_NUM"

	[[ -n $part ]] && qc_bump_base_version "$part"

	if [[ $target_channel == "stable" ]]; then
		QC_CHANNEL="stable"
		QC_PRERELEASE_NUM=""
	else
		if [[ $QC_BASE_VERSION == "$old_base" && $target_channel == "$old_channel" && -n $old_pre ]]; then
			QC_PRERELEASE_NUM=$((old_pre + 1))
		else
			QC_PRERELEASE_NUM=1
		fi
		QC_CHANNEL="$target_channel"
	fi

	qc_compute_full_version
	if [[ $QC_FULL_VERSION == "$current_full" ]]; then
		return 0
	fi

	QC_STATE_BASE="$QC_BASE_VERSION"
	QC_STATE_CHANNEL="$QC_CHANNEL"
	QC_STATE_PRE="$QC_PRERELEASE_NUM"
	QC_EXPECT_SUCCESS=1
	QC_EXPECT_VERSION="$QC_FULL_VERSION"
}

run_randomized_quickcheck_cases() {
	local case_name="randomized quickcheck transitions"
	local trials="${QUICKCHECK_TRIALS:-20}"
	local max_steps="${QUICKCHECK_MAX_STEPS:-7}"

	local trial
	for ((trial = 1; trial <= trials; trial++)); do
		local workdir
		workdir="$(mktemp -d)"
		local repo_dir="$workdir/repo"
		local remote_dir="$workdir/remote.git"
		local setup_log="$workdir/setup.log"
		CURRENT_LOG="$setup_log"

		prepare_case_repo "$repo_dir" "$remote_dir"
		qc_oracle_init

		local steps=$((1 + RANDOM % max_steps))
		local step
		for ((step = 1; step <= steps; step++)); do
			local step_log="$workdir/trial-${trial}-step-${step}.log"
			local before_version
			before_version="$(version_from_file "$repo_dir")"
			local cmd_display=""
			local step_result=""
			local before_head
			before_head="$(git -C "$repo_dir" rev-parse HEAD)"

			local oracle_before
			oracle_before="$(qc_oracle_current_full)"
			qc_build_random_command "$oracle_before"
			qc_oracle_apply "${QC_CMD_ARGS[@]}"
			cmd_display="${QC_CMD_ARGS[*]}"

			{
				echo "[test] randomized trial=$trial/$trials step=$step/$steps"
				echo "[test] command: ${QC_CMD_ARGS[*]}"
				echo "[test] expect_success=$QC_EXPECT_SUCCESS expect_version=$QC_EXPECT_VERSION"
			} >"$step_log"
			CURRENT_LOG="$step_log"

			set +e
			run_release "$repo_dir" "${QC_CMD_ARGS[@]}" >>"$step_log" 2>&1
			local status=$?
			set -e

			if [[ $QC_EXPECT_SUCCESS -eq 1 ]]; then
				if [[ $status -ne 0 ]]; then
					fail "$case_name: trial $trial step $step expected success for '${QC_CMD_ARGS[*]}'"
				fi

				local got_version
				got_version="$(version_from_file "$repo_dir")"
				assert_eq "$QC_EXPECT_VERSION" "$got_version" "$case_name: trial $trial step $step VERSION mismatch for '${QC_CMD_ARGS[*]}'"
				step_result="$got_version"

				if ! git -C "$repo_dir" tag --list | grep -qx "v$QC_EXPECT_VERSION"; then
					fail "$case_name: trial $trial step $step expected tag v$QC_EXPECT_VERSION for '${QC_CMD_ARGS[*]}'"
				fi
			else
				if [[ $status -eq 0 ]]; then
					fail "$case_name: trial $trial step $step expected failure for '${QC_CMD_ARGS[*]}'"
				fi

				local got_version
				got_version="$(version_from_file "$repo_dir")"
				assert_eq "$before_version" "$got_version" "$case_name: trial $trial step $step VERSION changed on failure for '${QC_CMD_ARGS[*]}'"
				step_result="fail (unchanged: $got_version)"

				local after_head
				after_head="$(git -C "$repo_dir" rev-parse HEAD)"
				assert_eq "$before_head" "$after_head" "$case_name: trial $trial step $step HEAD changed on failure for '${QC_CMD_ARGS[*]}'"
			fi

			echo "[test] PASS: randomized quickcheck trial $trial/$trials step $step/$steps from $before_version run '$cmd_display' -> $step_result" >&2
		done

		echo "[test] PASS: randomized quickcheck trial $trial/$trials" >&2

		rm -rf "$workdir"
		CURRENT_LOG=""
	done

	echo "[test] PASS: $case_name ($trials trials)" >&2
}

run_case() {
	local case_name="$1"
	local command_args="$2"
	local expected_version="$3"

	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/repo"
	local remote_dir="$workdir/remote.git"
	CURRENT_LOG="$workdir/case.log"

	prepare_case_repo "$repo_dir" "$remote_dir"

	run_capture_ok "$case_name: release command failed ($command_args)" run_release "$repo_dir" $command_args

	local got_version
	got_version="$(version_from_file "$repo_dir")"
	assert_eq "$expected_version" "$got_version" "$case_name: VERSION mismatch"

	if ! git -C "$repo_dir" tag --list | grep -qx "v$expected_version"; then
		fail "$case_name: expected tag v$expected_version was not created"
	fi

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_set_prerelease_then_full_case() {
	local case_name="set prerelease then full promotes to stable"

	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/repo"
	local remote_dir="$workdir/remote.git"
	CURRENT_LOG="$workdir/case.log"

	prepare_case_repo "$repo_dir" "$remote_dir"

	run_capture_ok "$case_name: release set failed" run_release "$repo_dir" set 1.1.5-beta.1
	run_capture_ok "$case_name: release full failed" run_release "$repo_dir" full

	local got_version
	got_version="$(version_from_file "$repo_dir")"
	assert_eq "1.1.5" "$got_version" "$case_name: VERSION mismatch"

	if ! git -C "$repo_dir" tag --list | grep -qx "v1.1.5"; then
		fail "$case_name: expected tag v1.1.5 was not created"
	fi

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_set_stable_then_full_noop_case() {
	local case_name="set stable then full fails with no-op"

	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/repo"
	local remote_dir="$workdir/remote.git"
	CURRENT_LOG="$workdir/case.log"

	prepare_case_repo "$repo_dir" "$remote_dir"

	run_capture_ok "$case_name: release set failed" run_release "$repo_dir" set 1.1.5

	local before_head
	before_head="$(git -C "$repo_dir" rev-parse HEAD)"

	local err_file="$workdir/full.err"
	set +e
	run_release "$repo_dir" full >"$err_file" 2>&1
	local status=$?
	set -e
	cat "$err_file" >>"$CURRENT_LOG"

	if [[ $status -eq 0 ]]; then
		fail "$case_name: expected release full to fail on no-op version"
	fi

	assert_contains "Version 1.1.5 is already current; nothing to do." "$err_file" "$case_name: missing no-op message"

	local after_head
	after_head="$(git -C "$repo_dir" rev-parse HEAD)"
	assert_eq "$before_head" "$after_head" "$case_name: HEAD changed despite no-op failure"

	local got_version
	got_version="$(version_from_file "$repo_dir")"
	assert_eq "1.1.5" "$got_version" "$case_name: VERSION changed after no-op failure"

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_set_stable_from_prerelease_requires_full_case() {
	local case_name="set stable from prerelease requires full"

	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/repo"
	local remote_dir="$workdir/remote.git"
	CURRENT_LOG="$workdir/case.log"

	prepare_case_repo "$repo_dir" "$remote_dir"

	run_capture_ok "$case_name: release set prerelease failed" run_release "$repo_dir" set 1.1.5-beta.1

	local before_head
	before_head="$(git -C "$repo_dir" rev-parse HEAD)"

	local err_file="$workdir/set-stable.err"
	set +e
	run_release "$repo_dir" set 1.1.5 >"$err_file" 2>&1
	local status=$?
	set -e
	cat "$err_file" >>"$CURRENT_LOG"

	if [[ $status -eq 0 ]]; then
		fail "$case_name: expected release set stable to fail from prerelease"
	fi

	assert_contains "promote using 'stable' or 'full' only" "$err_file" "$case_name: missing guardrail message"

	local after_head
	after_head="$(git -C "$repo_dir" rev-parse HEAD)"
	assert_eq "$before_head" "$after_head" "$case_name: HEAD changed despite guardrail failure"

	local got_version
	got_version="$(version_from_file "$repo_dir")"
	assert_eq "1.1.5-beta.1" "$got_version" "$case_name: VERSION changed after guardrail failure"

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_patch_stable_from_prerelease_requires_full_case() {
	local case_name="patch stable from prerelease requires full"

	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/repo"
	local remote_dir="$workdir/remote.git"
	CURRENT_LOG="$workdir/case.log"

	prepare_case_repo "$repo_dir" "$remote_dir"

	run_capture_ok "$case_name: release set prerelease failed" run_release "$repo_dir" set 1.1.5-beta.1

	local before_head
	before_head="$(git -C "$repo_dir" rev-parse HEAD)"

	local err_file="$workdir/patch-stable.err"
	set +e
	run_release "$repo_dir" patch stable >"$err_file" 2>&1
	local status=$?
	set -e
	cat "$err_file" >>"$CURRENT_LOG"

	if [[ $status -eq 0 ]]; then
		fail "$case_name: expected release patch stable to fail from prerelease"
	fi

	assert_contains "promote using 'stable' or 'full' only" "$err_file" "$case_name: missing guardrail message"

	local after_head
	after_head="$(git -C "$repo_dir" rev-parse HEAD)"
	assert_eq "$before_head" "$after_head" "$case_name: HEAD changed despite guardrail failure"

	local got_version
	got_version="$(version_from_file "$repo_dir")"
	assert_eq "1.1.5-beta.1" "$got_version" "$case_name: VERSION changed after guardrail failure"

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_case "channel-only from stable bumps patch" "beta" "1.0.1-beta.1"
run_case "explicit minor bump keeps requested bump" "minor beta" "1.1.0-beta.1"
run_set_prerelease_then_full_case
run_set_stable_then_full_noop_case
run_set_stable_from_prerelease_requires_full_case
run_patch_stable_from_prerelease_requires_full_case
run_randomized_quickcheck_cases

echo "[test] All release tests passed" >&2
