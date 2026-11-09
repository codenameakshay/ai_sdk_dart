# Depend on the packages from git

Until a version is on pub.dev, an app can pin the packages to one commit of this repository. Use the same
`url` and `ref` for every package from this repository, and add no `dependency_overrides`:

```yaml
dependencies:
  flutter: {sdk: flutter}
  ai_sdk_openui:
    git: {url: https://github.com/codenameakshay/ai_sdk_dart.git, ref: <commit-sha>, path: packages/ai_sdk_openui}
  open_intelligent_ui_core:
    git: {url: https://github.com/codenameakshay/ai_sdk_dart.git, ref: <commit-sha>, path: packages/open_intelligent_ui_core}
```

The same works for the other Open Intelligent UI packages (`open_intelligent_ui_chat`, `_maps`, `_math`,
`_web` and `open_intelligent_ui`): list each one you use with the same `url` and `ref`.

## How it works

A package depends on a sibling whose current version is not released yet (its CHANGELOG heading says
"unreleased") with a `path:` dependency. Inside a git dependency, pub resolves that path from the same
commit, so it matches the app's own git entry. A hosted constraint such as `^3.1.0` would point at pub.dev
instead and fail to resolve.

`tool/git_dependencies_test.dart` fails if a package uses a hosted constraint on an unreleased sibling.
The `git-consumer` CI job runs `tool/git_consumer_check.sh`, which creates a scratch Flutter app with the
dependencies above at the commit under test and runs `flutter pub get` and `flutter analyze --fatal-infos`.
To run it locally on a commit you have:

```sh
tool/git_consumer_check.sh "file://$PWD" "$(git rev-parse HEAD)"
```

pub.dev does not accept path dependencies, so `make dry-run` and `make publish` run
`tool/hosted_deps.dart` first. It replaces each sibling path dependency with `^<sibling version>` and
puts the pubspecs back when the publish ends.
