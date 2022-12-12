BUILD_CONTENT = """
sh_binary(
    name = "clang_tidy",
    srcs = ["run_clang_tidy.sh"],
    data = [":llvm-{llvm_version}/bin/clang-tidy", "//:clang_tidy_config"],
    tags = ["no-sandbox"],
    visibility = ["//visibility:public"],
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

filegroup(
    name = "clang_tidy_config_default",
    data = [
        ".clang-tidy",
        # '//example:clang_tidy_config', # add package specific configs if needed
    ],
)

label_flag(
    name = "clang_tidy_config",
    build_setting_default = ":clang_tidy_config_default",
    visibility = ["//visibility:public"],
)
"""


RUNFILES_INIT = """
# --- begin runfiles.bash initialization ---
# Copy-pasted from Bazel's Bash runfiles library (tools/bash/runfiles/runfiles.bash).
set -euo pipefail
if [[ ! -d "${RUNFILES_DIR:-/dev/null}" && ! -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  if [[ -f "$0.runfiles_manifest" ]]; then
    export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
  elif [[ -f "$0.runfiles/MANIFEST" ]]; then
    export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
  elif [[ -f "$0.runfiles/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
    export RUNFILES_DIR="$0.runfiles"
  fi
fi
if [[ -f "${RUNFILES_DIR:-/dev/null}/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
  source "${RUNFILES_DIR}/bazel_tools/tools/bash/runfiles/runfiles.bash"
elif [[ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  source "$(grep -m1 "^bazel_tools/tools/bash/runfiles/runfiles.bash " \
            "$RUNFILES_MANIFEST_FILE" | cut -d ' ' -f 2-)"
else
  echo >&2 "ERROR: cannot find @bazel_tools//tools/bash/runfiles:runfiles.bash"
  exit 1
fi
# --- end runfiles.bash initialization ---
"""


RUN_CLANG_TIDY_SH = """
set -ue

# Usage: run_clang_tidy <OUTPUT> [ARGS...]

OUTPUT=$1
shift

# clang-tidy doesn't create a patchfile if there are no errors.
# make sure the output exists, and empty if there are no errors,
# so the build system will not be confused.
rm -f $OUTPUT
touch $OUTPUT

function rewrite_argument {{
  ARG="$1"
  ARG="${{ARG//__BAZEL_XCODE_DEVELOPER_DIR__/$DEVELOPER_DIR}}"
  ARG="${{ARG//__BAZEL_XCODE_SDKROOT__/$SDKROOT}}"
  echo "$ARG"
}}

ARGS=()
for ARG in "$@" ; do
  ARGS+=("$(rewrite_argument "$ARG")")
done

CLANG_TIDY=$(rlocation "{repo_name}/llvm-{llvm_version}/bin/clang-tidy")
LLVM_HOME=$(readlink $(dirname $(dirname $CLANG_TIDY)))
"$CLANG_TIDY" "${{ARGS[@]}}" '-DNS_FORMAT_ARGUMENT(A)='
EXECUTION_ROOT="$(pwd)"
sed -i '' "s=$EXECUTION_ROOT/==g" "$OUTPUT"
sed -i '' "s=$EXECUTION_ROOT==g" "$OUTPUT"
sed -i '' "s=$LLVM_HOME=external/{repo_name}/llvm-{llvm_version}=g" "$OUTPUT"
"""


DOT_CLANG_TIDY = """
UseColor: true

Checks: >
    bugprone-*,
    cppcoreguidelines-*,
    google-*,
    performance-*,
HeaderFilterRegex: ".*"

WarningsAsErrors: "*"
"""


def _llvm_repo_impl(ctx):
    """Implementation of the llvm_repo rule."""
    llvm_home = ctx.os.environ["LLVM_HOME"]
    llvm_version = ctx.attr.llvm_version
    clang_tidy_version = ctx.execute(["{0}/bin/clang-tidy".format(llvm_home), "--version"])
    if clang_tidy_version.return_code != 0:
        fail("Failed to run clang-tidy.")
    if "LLVM version {0}".format(llvm_version) not in clang_tidy_version.stdout:
        fail("LLVM version not match.")
    ctx.file("BUILD",
             BUILD_CONTENT.format(llvm_version=llvm_version),
             executable=False)
    ctx.file("run_clang_tidy.sh",
             RUNFILES_INIT+RUN_CLANG_TIDY_SH.format(repo_name=ctx.name,
                                                    llvm_version=llvm_version),
             executable=True)
    ctx.file(".clang-tidy", DOT_CLANG_TIDY, executable=False)
    ctx.symlink(llvm_home, "llvm-"+llvm_version)


_llvm_repo_attrs = {
    "llvm_version": attr.string(doc='LLVM version', mandatory=True)
}


llvm_repo = repository_rule(
    implementation = _llvm_repo_impl,
    attrs = _llvm_repo_attrs,
    doc = "Setup llvm repo.",
    environ = ["LLVM_HOME"],
)
