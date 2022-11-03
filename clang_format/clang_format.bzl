load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")

def _run_tidy(ctx, exe, infile, discriminator):
    inputs = depset(direct = [infile])

    args = ctx.actions.args()

    # specify the output file - twice
    outfile = ctx.actions.declare_file(
        "bazel_clang_format_" + infile.path + "." + discriminator + ".clang-format.yaml"
    )

    args.add(outfile.path)  # this is consumed by the wrapper script
    args.add("-n")
    args.add("--Werror")

    # add source to check
    args.add(infile.path)

    ctx.actions.run(
        inputs = inputs,
        outputs = [outfile],
        executable = exe,
        arguments = [args],
        mnemonic = "ClangFormat",
        progress_message = "Run clang-format on {}".format(infile.short_path),
        execution_requirements = {
            # without "no-sandbox" flag the clang-format can not find a .clang-format file in the
            # closest parent, because the .clang-format file is placed in a "clang_format" shell
            # script runfiles, which is not a parent directory for any C/C++ source file
            "no-sandbox": "1",
        },
    )
    return outfile

def _rule_sources(ctx):
    files = []
    for attr_name in ["srcs", "hdrs"]:
        if hasattr(ctx.rule.attr, attr_name):
            for src in getattr(ctx.rule.attr, attr_name):
                files += [src for src in src.files.to_list() if src.is_source]
    return files

def _clang_format_aspect_impl(target, ctx):
    # if not a C/C++ target, we are not interested
    if not CcInfo in target:
        return []
    # if str(target.label) in ctx.attr.skip_targets:
    #     return []

    exe = ctx.attr._clang_format.files_to_run
    files = _rule_sources(ctx)
    if not files:
        return []
    outputs = [_run_tidy(ctx, exe, each_file, target.label.name) for each_file in files]
    return [
        OutputGroupInfo(report = depset(direct = outputs)),
    ]

clang_format_aspect = aspect(
    implementation = _clang_format_aspect_impl,
    fragments = ["cpp", "apple", "objc"],
    attrs = {
        "_clang_format": attr.label(default = Label("//:clang_format")),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
)
