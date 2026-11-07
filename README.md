# KeyChat

A small Flutter chat app that uses **your own API key**: paste a key once, keep
it on the device, and chat with the model anytime. No account, no backend — the
phone talks straight to the provider.

## What it does

- Asks for an API key on first launch and stores it in the platform keystore
  (`flutter_secure_storage`), so it survives restarts.
- Works with any OpenAI-compatible endpoint. The base URL defaults to
  `https://api.openai.com/v1` and can be changed to OpenRouter, Groq, Together,
  Mistral, a local Ollama `/v1`, and so on.
- "Load models from this endpoint" fetches `/models` and fills the model name,
  so you pick from what the key can actually use.
- Streams replies token by token, with stop and a clear-chat action.
- Keeps the last conversation on the device between launches.

## Run it

```sh
cd flutter_chat
flutter pub get
flutter run            # pick a connected device or emulator
```

Build an installable APK:

```sh
flutter build apk --release
```

## Layout

- `lib/main.dart` — theme and startup; loads saved settings before the chat.
- `lib/services/settings_store.dart` — key in secure storage, endpoint/model and
  conversation history in `shared_preferences`.
- `lib/services/chat_api.dart` — streaming chat completions, `/models` listing,
  readable errors (401 key rejected, 404 model missing, 429 limits, …).
- `lib/screens/chat_screen.dart` — thread, composer, stop, new chat.
- `lib/screens/settings_screen.dart` — key, base URL, model picker.

## Notes

- The key never leaves the device except in the `Authorization` header sent to
  the endpoint you configure.
- Requests need internet access (already allowed in the Android manifest).
- HTTP (not HTTPS) endpoints are blocked by Android/iOS by default; use an
  HTTPS endpoint or add a network-security exception if you really need plain
  HTTP for a local model.
