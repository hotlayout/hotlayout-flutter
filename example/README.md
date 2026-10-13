# HotLayout example

The quickstart of [`hotlayout_flutter`](../README.md) as a complete app: a published document on screen with a bundled copy underneath, data from the host, a host action and the device language.

```bash
flutter run -d chrome          # the bundled copies only
flutter run -d chrome \
  --dart-define=documentUrl=https://example.com/published.json \
  --dart-define=themeUrl=https://example.com/theme.json
flutter test
```

Only the `web/` platform folder is committed. For a device, generate the others once:

```bash
flutter create --platforms=android,ios,macos .
```

and then give the app network access — see "Platform notes" in the package README (the `INTERNET` permission in the main Android manifest, the `network.client` entitlement on macOS). Without it every request silently falls back to the bundled copies.

| File | What it shows |
|---|---|
| `lib/main.dart` | The whole host: theme before the first frame, bundled copy then network, drawing, actions, language. |
| `lib/backend.dart` | The data the document is bound to: flat paths, nested maps, collections. |
| `lib/recipes.dart` | Pieces to add when needed: data of one screen, refresh without a reset, a version check, your own HTTP client, labels, a theme picker. |
| `assets/hotlayout/` | The bundled copies: the `rewards-showcase` contract fixture and its theme. |

Every Dart snippet of the package README is a verbatim fragment of these files; `test/public_api_test.dart` of the package fails when one of them stops matching.
