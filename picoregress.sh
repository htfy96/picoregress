#!/usr/bin/env bash

set -euo pipefail

# Returns 0 if color is enabled, 1 otherwise
color_enabled() {
  if [[ ${NO_COLOR+unset} == "unset" ]]; then
    return 1
  fi
  if [[ ! -t 0 ]]; then
    return 1
  fi
  return 0
}

# $1: style (in bold, boldgreen, boldred, green, red, dim, dimgreen, dimred)
# $2: string to colorize
# Print the colorized string (no line end)
colorize() {
  if ! color_enabled; then
    echo -n "$2"
    return
  fi
  if [[ -z $1 ]]; then
    echo -n "$2"
    return
  fi
  local res
  res="$2"
  if [[ $1 == "dim" || $1 == "dimgreen" || $1 == "dimred" ]]; then
    res=$(tput dim)"$res"$(tput sgr0)
  fi
  if [[ $1 == "bold" || $1 == "boldgreen" || $1 == "boldred" ]]; then
    res=$(tput bold)"$res"$(tput sgr0)
  fi
  if [[ $1 == "red" || $1 == "boldred" || $1 == "dimred" ]]; then
    res=$(tput setaf 1)"$res"$(tput sgr0)
  fi
  if [[ $1 == "green" || $1 == "boldgreen" || $1 == "dimgreen" ]]; then
    res=$(tput setaf 2)"$res"$(tput sgr0)
  fi
  echo -n "$res"
}

# Ensure it's Bash 4.2+, else bail out
check_bash_version() {
  if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 2))); then
    echo >&2 "Bash version too low! Current: ${BASH_VERSION}. Requires >= 4.2"
    echo >&2 ""
    echo >&2 "If you are on Mac OS, install the latest via brew install bash instead using system defaults"
    exit 1
  fi
}

# Sets TEST_CASE_FILES (array)
# and OUTPUT_DIR (string)
parse_config() {
  if [[ ! -f "picoregress.cfg" ]]; then
    echo >&2 "picoregress.cfg not found in current directory"
    exit 1
  fi
  declare -ag TEST_CASE_FILES=()
  declare -g OUTPUT_DIR
  while read -r line; do
    local key
    local val
    IFS="=" read -r key val <<<"$line"
    case "$key" in
    output_dir)
      OUTPUT_DIR=$(readlink -f "$(pwd)/$val")
      if [[ ! -d $OUTPUT_DIR ]]; then
        echo >&2 "Output dir ${OUTPUT_DIR} not found"
        exit 1
      fi
      ;;
    test_case_files)
      local raw_test_case_files
      IFS="," read -r -a raw_test_case_files <<<"$val"
      for raw_test_case_file in "${raw_test_case_files[@]}"; do
        local test_case_file
        test_case_file=$(readlink -f "$(pwd)"/"${raw_test_case_file}")
        if [[ ! -f $test_case_file ]]; then
          echo >&2 "Test case file ${test_case_file} not found"
          exit 1
        fi
        TEST_CASE_FILES+=("$test_case_file")
      done
      ;;
    *)
      echo >&2 "Unknown key in picoregress.cfg " "$key"
      exit 1
      ;;
    esac
  done <"picoregress.cfg"
  if ((${#TEST_CASE_FILES[@]} == 0)); then
    echo >&2 "Missing test_case_files=file1,file2 in picoregress.cfg"
    exit 1
  fi
  if [[ -z $OUTPUT_DIR ]]; then
    echo >&2 "Missing test_case_files=file1,file2 in picoregress.cfg"
    exit 1
  fi

  echo >&2 "Using output_dir $OUTPUT_DIR and TEST_CASE_FILES " "${TEST_CASE_FILES[@]}"
}

# Read TEST_CASE_FILES
# and parse test case description
# Populate TEST_CASES
read_test_case_files() {
  declare -Ag TEST_CASES=()
  local test_case_file
  for test_case_file in "${TEST_CASE_FILES[@]}"; do
    local test_case
    while IFS="" read -r test_case; do
      local name
      name=$(echo "$test_case" | cut -d'=' -f1)
      local args
      args=$(echo "$test_case" | cut -d'=' -f2-)
      if [[ -n ${TEST_CASES[$name]+x} ]]; then
        echo >&2 "Duplicated test case name ${name}. Previous definiton ${TEST_CASES[${name}]}"
      fi
      TEST_CASES["$name"]="$args"
    done <"$test_case_file"
  done
}

usage() {
  cat >&2 <<EOF
  Usage:
  picoregress.sh {COMMAND} [args...]

  Commands:
    list: list all regression test cases and output status
    output-dir {test case name}: print out the test case output dir
    run [test case name regex] [-u | -x]: run test and diff output. Specifying -u auto-updates changed hashes. -x skips hash update.

  Current directory should contain a file called picoregress.cfg, which specifies:

  output_dir={The directory to store output, relative to .cfg}
  test_case_files=test_case_file1,test_case_file2

  Each test_case_file should have a format of:

  name=COMMAND

  The COMMAND can be any valid shell script.

  picoregress.sh sets a few additional environment variables during the run:
  - PICORG=1
  - PICORG_TEST_CASE={test_case_name}
  - PICORG_OUTPUT_DIR={output_dir}
EOF
}

# Arg: $1: file path
print_file_summary() {
  local -r remain="${1%/*}"
  local -r last="${1##*/}"
  echo "$remain/$(colorize bold "$last")"
  if [[ ! -f $1 ]]; then
    echo "Non-existent"
    return
  fi

  local -r checksum=$(sha256sum "$1" | head -c 8)
  echo "    Last Modified: " "$(stat -c "%Y" "$1" | xargs -I{} date -d"@{}")" ". Sha256sum: $(colorize bold "$checksum")"
  if color_enabled; then
    tput dim
  fi
  if [[ ! -s $1 ]]; then
    echo "    File is empty"
  else
    head -3 "$1" | sed 's/^/  > /'
  fi
  if color_enabled; then
    tput sgr0
  fi
}

# $1: test_case_regex
list_test_cases() {
  local test_case
  for test_case in "${!TEST_CASES[@]}"; do
    if [[ $test_case =~ $1 ]]; then
      echo "============"
      echo "$(colorize bold "Test case ${test_case}")"
      echo "------------"
      print_file_summary "$OUTPUT_DIR/$test_case/stderr"
      print_file_summary "$OUTPUT_DIR/$test_case/stdout"
    fi
  done
}

# Run test case in a temp dir, and returns the temporary output dir
# Args:
# $1 test case name
run_test_case() {
  echo >&2 "Running test case $1: ${TEST_CASES[$1]}"
  local fail_flag=""
  local output_dir
  output_dir=$(mktemp -d)
  /usr/bin/env PICORG=1 PICORG_TEST_CASE="$1" PICORG_OUTPUT_DIR="$output_dir" bash -c "${TEST_CASES[$1]}" >"${output_dir}"/stdout 2>"${output_dir}"/stderr || fail_flag=1
  if [[ $fail_flag == 1 ]]; then
    echo >&2 "Failed to run ${TEST_CASES[$1]}. Check output at $output_dir"
    return
  fi
  echo "$output_dir"
}

# Arg1: Pattern
# Arg2: update_flag:
#   "yes": auto update all changed hashes
#   "no": never update changed hashes
#   Unset/empty: prompt
run_test_cases() {
  local test_case
  local -r auto_update="$2"
  declare -a changed_cases=()
  declare -A output_dirs=()
  for test_case in "${!TEST_CASES[@]}"; do
    if [[ $test_case =~ $1 ]]; then
      echo "============"
      echo "$(colorize bold "Test case ${test_case}")"
      echo "------------"
      local output_dir
      output_dir=$(run_test_case "${test_case}")
      output_dirs[$test_case]="$output_dir"
      if [[ -z $output_dir ]]; then
        continue
      fi
      mkdir -p "$OUTPUT_DIR/$test_case"
      if diff -rq "$output_dir" "$OUTPUT_DIR/$test_case" >/dev/null; then
        echo "$(colorize dimgreen "    Unchanged!")"
      else
        changed_cases+=("$test_case")
        echo ">>> OLD"
        echo "$(colorize red "$(print_file_summary "$OUTPUT_DIR/$test_case/stderr")")"
        echo "$(colorize red "$(print_file_summary "$OUTPUT_DIR/$test_case/stdout")")"
        echo "<<< NEW"
        echo "$(colorize green "$(print_file_summary "$output_dir/stderr")")"
        echo "$(colorize green "$(print_file_summary "$output_dir/stdout")")"
        echo "<<< DIFF >>>"
        if color_enabled; then
          tput dim
        fi
        diff -ru3 "$OUTPUT_DIR/$test_case" "$output_dir/" | sed 's/^/  > /' || true
        if color_enabled; then
          tput sgr0
        fi
      fi
    fi
  done

  if [[ $auto_update != "no" && (${#changed_cases[@]} -gt 0) ]]; then
    echo "=========================="
    echo "Changed cases:"
    local i
    for ((i = 0; i < ${#changed_cases[@]}; i++)); do
      printf "%3s: %s\n" $((i + 1)) "${changed_cases[$i]}"
    done
    echo "=========================="
    echo ""
    local prompt
    if [[ $auto_update != "yes" ]]; then
      echo -n "Enter a regex to specify cases to update: "
      read -r prompt
      if [[ -z $prompt ]]; then
        return
      fi
    else
      prompt=".*"
    fi
    for test_case in "${changed_cases[@]}"; do
      if [[ $test_case =~ $prompt ]]; then
        echo -n "Updating" "$(colorize bold "$test_case")..."
        output_dir="${output_dirs[$test_case]}"
        cp -rf "$output_dir"/* "$OUTPUT_DIR/$test_case/"
        echo "$(colorize boldgreen " Updated!")"
      fi
    done
  fi
  return "${#changed_cases[@]}"
}

# $1: test_case_name
print_output_dir() {
  if [[ ! -v "TEST_CASES[$1]" ]]; then
    echo >&2 "Cannot find test case $1"
    exit 1
  fi
  echo "$OUTPUT_DIR/$1"
}

main() {
  check_bash_version
  parse_config
  read_test_case_files
  if [[ $# == 0 ]]; then
    usage
    exit 0
  fi
  local -r cmd="$1"
  shift 1
  case "$cmd" in
  list)
    list_test_cases "${1:-.*}"
    ;;
  run)
    local auto_update_flag=""
    while getopts ":ux" o; do
      case "$o" in
      u)
        auto_update_flag="yes"
        shift
        ;;
      x)
        auto_update_flag="no"
        shift
        ;;
      *)
        echo >&2 "Unknown args $o"
        exit 1
        ;;
      esac
    done
    run_test_cases "${1:-.*}" "$auto_update_flag"
    exit "$?"
    ;;
  "output-dir")
    print_output_dir "$1"
    ;;
  *)
    echo >&2 "Unsupported command $cmd"
    usage
    exit 1
    ;;
  esac
}

main "$@"
