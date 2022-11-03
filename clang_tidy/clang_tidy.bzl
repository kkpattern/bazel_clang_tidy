load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")

def _run_tidy(ctx, exe, compilation_context, infile, discriminator):
    cc_toolchain = find_cpp_toolchain(ctx)
    cpu = cc_toolchain.cpu
    toolchain_flags = _toolchain_flags(ctx, infile.extension)
    rule_flags = ctx.rule.attr.copts if hasattr(ctx.rule.attr, "copts") else []
    flags = _safe_flags(toolchain_flags + rule_flags)

    inputs = depset(direct = [infile], transitive = [compilation_context.headers])

    args = ctx.actions.args()

    # specify the output file - twice
    outfile = ctx.actions.declare_file(
        "bazel_clang_tidy_" + infile.path + "." + discriminator + ".clang-tidy.yaml"
    )

    args.add(outfile.path)  # this is consumed by the wrapper script
    args.add("--export-fixes", outfile.path)

    # add source to check
    args.add(infile.path)

    # start args passed to the compiler
    args.add("--")

    env = {}
    if cpu == "ios_arm64":
        # TODO: we should extract this from toolchain. but how?
        if infile.extension in ["m", "mm"]:
            args.add("-arch")
            args.add("arm64")
        xcode_config = ctx.attr._xcode_config[apple_common.XcodeVersionConfig]
        env.update(apple_common.apple_host_system_env(xcode_config))
        env.update(apple_common.target_apple_env(xcode_config, ctx.fragments.apple.single_arch_platform))
    else:
        # XXX: run clang tidy脚本里会用DEVELOPER_DIR替换__BAZEL_XCODE_DEVELOPER_DIR__
        # 只有iOS才需要. 但是为了兼容对于非iOS我们将这个环境变量设置一下.
        env["DEVELOPER_DIR"] = "__BAZEL_XCODE_DEVELOPER_DIR__"
        env["SDKROOT"] = "__BAZEL_XCODE_SDKROOT__"

    # add args specified by the toolchain, on the command line and rule copts
    args.add_all(flags)

    # add defines
    for define in compilation_context.defines.to_list():
        args.add("-D" + define)

    for define in compilation_context.local_defines.to_list():
        args.add("-D" + define)

    # add includes
    for i in compilation_context.framework_includes.to_list():
        args.add("-F" + i)

    for i in compilation_context.includes.to_list():
        args.add("-I" + i)

    args.add_all(compilation_context.quote_includes.to_list(), before_each = "-iquote")

    args.add_all(compilation_context.system_includes.to_list(), before_each = "-isystem")

    # args.add("-Xclang")
    # args.add("-analyzer-config")
    # args.add("-Xclang")
    # args.add("crosscheck-with-z3=true")

    ctx.actions.run(
        inputs = inputs,
        outputs = [outfile],
        executable = exe,
        env = env,
        arguments = [args],
        mnemonic = "ClangTidy",
        progress_message = "Run clang-tidy on {}".format(infile.short_path),
        execution_requirements = {
            # without "no-sandbox" flag the clang-tidy can not find a .clang-tidy file in the
            # closest parent, because the .clang-tidy file is placed in a "clang_tidy" shell
            # script runfiles, which is not a parent directory for any C/C++ source file
            "no-sandbox": "1",
        },
    )
    return outfile

def _rule_sources(ctx):
    srcs = []
    if hasattr(ctx.rule.attr, "srcs"):
        for src in ctx.rule.attr.srcs:
            # sometimes internal headers are in srcs. We don't want to check them because
            # we don't know they're C or C++ headers.
            srcs += [src for src in src.files.to_list() if src.is_source and src.extension not in ["h", "inl"]]
    return srcs

def _toolchain_flags(ctx, file_extension="cpp"):
    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
    )
    if file_extension in ["cpp", "mm"]:
        user_compile_flags = ctx.fragments.cpp.cxxopts + ctx.fragments.cpp.copts
    else:
        user_compile_flags = ctx.fragments.cpp.copts
    compile_variables = cc_common.create_compile_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        user_compile_flags = user_compile_flags,
    )
    if file_extension == "c":
        action_name = "c-compile"
    elif file_extension == "m":
        action_name = "objc-compile"
    elif file_extension == "mm":
        action_name = "objc++-compile"
    else:
        action_name = "c++-compile" # tools/build_defs/cc/action_names.bzl CPP_COMPILE_ACTION_NAME
    flags = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = action_name,
        variables = compile_variables,
    )
    return flags

def _safe_flags(flags):
    # Some flags might be used by GCC, but not understood by Clang.
    # Remove them here, to allow users to run clang-tidy, without having
    # a clang toolchain configured (that would produce a good command line with --compiler clang)
    unsupported_flags = [
        "-fno-canonical-system-headers",
        "-fstack-usage",
    ]

    return [flag for flag in flags if flag not in unsupported_flags and not flag.startswith("--sysroot")]

def _clang_tidy_aspect_impl(target, ctx):
    # if not a C/C++ target, we are not interested
    if not CcInfo in target:
        return []


    exe = ctx.attr._clang_tidy.files_to_run
    srcs = _rule_sources(ctx)
    if not srcs:
        return []
    compilation_context = target[CcInfo].compilation_context
    outputs = [_run_tidy(ctx, exe, compilation_context, src, target.label.name) for src in srcs]

    return [
        OutputGroupInfo(report = depset(direct = outputs)),
    ]

clang_tidy_aspect = aspect(
    implementation = _clang_tidy_aspect_impl,
    fragments = ["cpp", "apple", "objc"],
    attrs = {
        "_cc_toolchain": attr.label(default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")),
        "_clang_tidy": attr.label(default = Label("//:clang_tidy")),
        "_xcode_config": attr.label(
            default = configuration_field(
                fragment = "apple",
                name = "xcode_config_label",
            ),
        ),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
)
