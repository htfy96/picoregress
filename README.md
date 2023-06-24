# picoregress

Picoregress is a minimal, single-file regression testing framework written in Bash 4.2. It acts as a helper to run, diff, store and update `stdout` and `stderr` of test commands.

[![asciicast](https://asciinema.org/a/593089.svg)](https://asciinema.org/a/593089)

## Usage

Download the script either into your project folder or to $PATH:

```
curl -sSL https://github.com/htfy96/picoregress/raw/master/picoregress.sh > picoregress.sh && chmod +x picoregress.sh
```

After that, create a `picoregress.cfg` containing two lines in your project root:

```
output_dir={The directory to store captured output, relative to project root}
test_case_files=comma_separated.txt,files.txt,describing_commands.txt
```

For each test_case_files, the syntax is:

```
test_case_name=Any Bash Command
test_case_2=Any Bash Command
```


Then, run `picoregress.sh run` at project root, and it will prompt interactively for updating hashes. You can specify the subset of tests to run via `picoregress.sh run {regex}`. Additionally, `run -u` automatically updates all hashes, while `run -x` skips the interactive prompt. Refer to the next section for detailed help.

## Command-line references

```

  Usage:
  picoregress.sh {COMMAND} [args...]

  Commands:
    list: list all regression test cases and output status
    output-dir {test case name}: print out the test case output dir
    run [-u | -x] [test case name regex]: run test and diff output. Specifying -u auto-updates changed hashes. -x skips hash update.

  Current directory should contain a file called picoregress.cfg, which specifies:

  output_dir={The directory to store output, relative to .cfg}
  test_case_files=test_case_file1,test_case_file2

  Each test_case_file should have a format of:

  name=COMMAND

  The COMMAND can be any valid shell script

  picoregress.sh sets a few additional environment variables during the run:
  - PICORG=1
  - PICORG_TEST_CASE={test_case_name}
  - PICORG_OUTPUT_DIR={output_dir}
```

## License
Apache v2
