#!/usr/bin/env bash

set -euo pipefail

# Ensure it's Bash 4.2+, else bail out
check_bash_version() {
  if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 1))); then
    echo >&2 "Bash version too low! Current: ${BASH_VERSION}. Requires >= 4.1"
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
    run [test case name regex]: run test and diff output
    update [test case name regex]: run test and update hash

  Current directory should contain a file called picoregress.cfg, which specifies:

  output_dir={The directory to store output, relative to .cfg}
  test_case_files=test_case_file1,test_case_file2

  Each test_case_file should have a format of:

  name=COMMAND

  The COMMAND can be any valid shell script
EOF
}

# Arg: $1: file path
print_file_summary() {
  echo -n "$1: "
  if [[ ! -f $1 ]]; then
    echo "Non-existent"
    return
  fi

  echo "Last Modified: $(stat -c "%Y" "$1" | xargs -I{} date -d"@{}"). Sha256sum: $(sha256sum "$1" | head -c 8)"
}

# $1: test_case_regex
list_test_cases() {
  local test_case
  for test_case in "${!TEST_CASES[@]}"; do
    if [[ $test_case =~ $1 ]]; then
      echo "============"
      echo "Test case ${test_case}"
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
  /usr/bin/env bash -c "${TEST_CASES[$1]}" >"${output_dir}"/stdout 2>"${output_dir}"/stderr || fail_flag=1
  if [[ $fail_flag == 1 ]]; then
    echo >&2 "Failed to run ${TEST_CASES[$1]}. Check output at $output_dir"
    return
  fi
  echo "$output_dir"
}

# Arg1: Pattern
update_test_case() {
  local test_case
  for test_case in "${!TEST_CASES[@]}"; do
    if [[ $test_case =~ $1 ]]; then
      echo "============"
      echo "Test case ${test_case}"
      echo "------------"
      echo ">>> OLD"
      print_file_summary "$OUTPUT_DIR/$test_case/stderr"
      print_file_summary "$OUTPUT_DIR/$test_case/stdout"
      local output_dir
      output_dir=$(run_test_case "${test_case}")
      if [[ -z $output_dir ]]; then
        continue
      fi
      echo "<<< NEW"
      print_file_summary "$output_dir/stderr"
      print_file_summary "$output_dir/stdout"
      cp -rf "$output_dir" "$OUTPUT_DIR/$test_case"
    fi
  done
}

main() {
  check_bash_version
  parse_config
  read_test_case_files
  if [[ $# == 0 ]]; then
    usage
    exit 0
  fi
  case "$1" in
  list)
    list_test_cases "${2:-.*}"
    ;;
  update)
    update_test_case "${2:-.*}"
    ;;
  *)
    echo >&2 "Unsupported command $1"
    usage
    exit 1
    ;;
  esac
}

main "$@"
