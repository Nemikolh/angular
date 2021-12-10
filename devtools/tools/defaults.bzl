# Re-export of Bazel rules with repository-wide defaults

load("@npm//@bazel/concatjs:index.bzl", _karma_web_test = "karma_web_test", _karma_web_test_suite = "karma_web_test_suite")
load("@npm//@angular/dev-infra-private/bazel/esbuild:index.bzl", _esbuild = "esbuild", _esbuild_config = "esbuild_config")
load("@npm//@angular/dev-infra-private/bazel/spec-bundling:index.bzl", _spec_bundle = "spec_bundle")
load("@npm//@angular/dev-infra-private/bazel:extract_js_module_output.bzl", "extract_js_module_output")
load("//tools/angular:index.bzl", "LINKER_PROCESSED_FW_PACKAGES")

esbuild = _esbuild
esbuild_config = _esbuild_config

def karma_web_test_suite(name, **kwargs):
    web_test_args = {}
    test_deps = kwargs.get("deps", [])

    kwargs["deps"] = ["%s_bundle" % name]

    spec_bundle(
        name = "%s_bundle" % name,
        deps = test_deps,
        platform = "browser",
    )

    # Set up default browsers if no explicit `browsers` have been specified.
    if not hasattr(kwargs, "browsers"):
        kwargs["tags"] = ["native"] + kwargs.get("tags", [])
        kwargs["browsers"] = [
            "@npm//@angular/dev-infra-private/bazel/browsers/chromium:chromium",

            # todo(aleksanderbodurri): enable when firefox support is done
            # "@npm//@angular/dev-infra-private/bazel/browsers/firefox:firefox",
        ]

    for opt_name in kwargs.keys():
        # Filter out options which are specific to "karma_web_test" targets. We cannot
        # pass options like "browsers" to the local web test target.
        if not opt_name in ["wrapped_test_tags", "browsers", "wrapped_test_tags", "tags"]:
            web_test_args[opt_name] = kwargs[opt_name]

    # Custom standalone web test that can be run to test against any browser
    # that is manually connected to.
    _karma_web_test(
        name = "%s_local_bin" % name,
        config_file = "//test:bazel-karma-local-config.js",
        tags = ["manual"],
        **web_test_args
    )

    # Workaround for: https://github.com/bazelbuild/rules_nodejs/issues/1429
    native.sh_test(
        name = "%s_local" % name,
        srcs = ["%s_local_bin" % name],
        tags = ["manual", "local", "ibazel_notify_changes"],
        testonly = True,
    )

    # Default test suite with all configured browsers.
    _karma_web_test_suite(
        name = name,
        **kwargs
    )

def spec_bundle(name, deps, **kwargs):
    extract_js_module_output(
        name = "%s_devmode_deps" % name,
        deps = deps,
        provider = "JSModuleInfo",
        forward_linker_mappings = True,
        include_external_npm_packages = True,
        include_default_files = False,
        include_declarations = False,
        testonly = True,
    )

    _spec_bundle(
        name = name,
        # For specs, we always add the pre-processed linker FW packages so that these
        # are resolved instead of the unprocessed FW entry-points through the `node_modules`.
        deps = ["%s_devmode_deps" % name] + LINKER_PROCESSED_FW_PACKAGES,
        workspace_name = "angular_devtools",
        run_angular_linker = True,
        **kwargs
    )