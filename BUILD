filegroup(
    name = "clang_tidy_config_default",
    srcs = [
        ".clang-tidy",
        # '//example:clang_tidy_config', # add package specific configs if needed
    ],
)

label_flag(
    name = "clang_tidy_config",
    build_setting_default = ":clang_tidy_config_default",
    visibility = ["//visibility:public"],
)

label_flag(
    name = "clang_tidy",
    build_setting_default = "//clang_tidy:clang_tidy",
    visibility = ["//visibility:public"],
)

filegroup(
    name = "clang_format_config_default",
    srcs = [
        ".clang-format",
        # '//example:clang_tidy_config', # add package specific configs if needed
    ],
)

label_flag(
    name = "clang_format_config",
    build_setting_default = ":clang_format_config_default",
    visibility = ["//visibility:public"],
)

label_flag(
    name = "clang_format",
    build_setting_default = "//clang_format:clang_format",
    visibility = ["//visibility:public"],
)
