# Architecture
Four separate responsibilities, each its own module/service boundary:
1. **Auth** - sign-in, short-lived access tokens.
2. **Room state** - WebSocket carrying control messages only (play/pause/seek/position, participants). Never video data.
3. **Media transport** - peer/relay streaming of the host's selected local file (Milestone 3).
4. **File delivery** - Google Drive proxy/signed access (Milestone 4).

Client: Flutter, feature-first folders, go_router, Riverpod. Server: Node 22 + Fastify.
Security: validate all requests/WS messages, rate limit, TLS, secrets via environment variables, local-file access limited to the user-selected file.
Data handling: document each external service (Google APIs, TURN/STUN provider) here when added.
