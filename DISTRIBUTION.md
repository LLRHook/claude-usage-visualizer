# Distribution

Claude Usage Bar is a native macOS menu bar app with Sparkle updates. A public release needs a signed and notarized app archive plus a Sparkle appcast.

## Preflight

```bash
make clean
make build
```

Run the app locally with `make run`, connect it to the mock server or a real Claude account, and verify:

- menu bar icon rendering
- popover charts and pace status
- settings persistence
- Sparkle update configuration

## Release Checklist

- Confirm `MARKETING_VERSION` and build number in the Xcode project.
- Build with Developer ID signing enabled.
- Notarize the archive with Apple notary credentials.
- Generate and sign the Sparkle appcast.
- Upload the `.dmg` or `.zip` and appcast to the update host.
- Update the README with the public download URL once the first release artifact is available.

## Repository Status

- CI now checks package resolution and debug build on macOS.
- License file is still required before public open-source distribution.
- Sparkle signing keys, Apple credentials, and update-host credentials must remain outside the repository.
