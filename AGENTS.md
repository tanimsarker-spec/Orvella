# Orvella conventions
- Flutter app in `app/` (feature-first: `lib/features/<name>/`), backend in `server/`.
- Four separate responsibilities: auth, room state (WebSocket, control messages only),
  media transport, file delivery. Never send video data over the sync WebSocket.
- Colors, fonts and radii live in `lib/theme/` only.
- Unimplemented screens use `PlaceholderScreen`; never fake data silently.
- Never commit secrets. Config comes from environment variables; see `.env.example`.
- Before pushing: `dart format .`, `flutter analyze`, `flutter test`; `npm test` in `server/`.
- Do not claim a platform builds unless the CI job for it is green.
