# Contributing

Issues and pull requests are welcome. Please describe the macOS version, Sushi version and the steps needed to reproduce a problem. Remove credentials, private paths and conversation contents from logs before sharing them.

For code changes, run the offline checks and build on Apple Silicon:

```sh
./macos/test.sh
./macos/build.sh
```

The optional compatibility checks in the README use a Sushi executable or server; run those only against a setup you are comfortable testing. Keep changes to the app independent from the user's running server and configuration.
