"""Run the module's shell tests with declared tools and runfiles."""

load("@jq.bzl//jq/toolchain:toolchain.bzl", "TOOLCHAIN_TYPE")

def _test_impl(ctx):
    executable = ctx.actions.declare_file(ctx.label.name + ".runner.sh")
    jq = ctx.toolchains[TOOLCHAIN_TYPE].jqinfo.bin
    ctx.actions.write(
        executable,
        '#!/usr/bin/env bash\nset -euo pipefail\ncd "$TEST_SRCDIR/$TEST_WORKSPACE"\nexec bash "' + ctx.file.script.short_path + '" "' + jq.short_path + '" "' + ctx.file.filters.short_path + '"\n',
        is_executable = True,
    )
    return [DefaultInfo(
        executable = executable,
        runfiles = ctx.runfiles(files = [jq, ctx.file.script, ctx.file.filters] + ctx.files.data),
    )]

report_test = rule(
    implementation = _test_impl,
    test = True,
    attrs = {
        "data": attr.label_list(allow_files = True),
        "filters": attr.label(allow_single_file = True, default = Label("//private:check.jq")),
        "script": attr.label(allow_single_file = True, mandatory = True),
    },
    toolchains = [TOOLCHAIN_TYPE],
)
