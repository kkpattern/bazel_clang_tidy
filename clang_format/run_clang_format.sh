#! /bin/bash
# Usage: run_clang_format <OUTPUT> [ARGS...]
set -ue

OUTPUT=$1
shift

# clang-tidy doesn't create a patchfile if there are no errors.
# make sure the output exists, and empty if there are no errors,
# so the build system will not be confused.
rm -rf $OUTPUT
touch $OUTPUT

clang-format "$@"
