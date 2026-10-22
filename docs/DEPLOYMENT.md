# Deployment

## 1. Server (needed so friends can connect with no VPN or router setup)
Friends and the host both connect OUT to your server, so nobody opens ports at home.
1. Get a small VPS (any provider) and a domain name with an A record pointing at it.
2. Install Docker. Copy this repo (or just `Dockerfile`, `server/`, `deploy/`) to the VPS.
3. `cd deploy && cp .env.example .env`, fill in `ORVELLA_DOMAIN` and `JWT_SECRET` (`openssl rand -hex 32`).
4. `docker compose up -d --build`. Caddy provisions HTTPS automatically.
5. Check `https://YOUR_DOMAIN/healthz` returns `{"status":"ok"}`.

Bandwidth: local-file and Drive streams pass THROUGH the server. A 4K file at 50 Mbit/s needs
50 Mbit/s of upload on the host's home connection AND 50 Mbit/s download+upload per viewer on the server.
Choose a VPS with enough bandwidth; measure it (see Quality screen).

## 2. Google Drive (optional)
1. Google Cloud Console -> new project -> enable "Google Drive API".
2. OAuth consent screen: External; add yourself and friends as **Test users**.
   `drive.readonly` is a restricted scope: public release needs Google verification. In Testing mode
   up to 100 test users work, and Google expires their authorization after 7 days (reconnect in the app).
3. Credentials -> Create OAuth client ID -> **Web application**.
   Authorized redirect URI: `https://YOUR_DOMAIN/drive/oauth/callback`
4. Put the client ID/secret in `deploy/.env`, then `docker compose up -d`.

## 3. App builds
In the GitHub repo: Settings -> Secrets and variables -> Actions -> **Variables** -> add
`ORVELLA_SERVER` = `https://YOUR_DOMAIN`. CI bakes this into the apps as the default server URL.

## 4. Data handling
- Display names and room membership are held in server memory (lost on restart). No emails or passwords are collected.
- Chat is relayed, never stored. Video bytes are relayed, never stored on the server.
- Google tokens are kept in server memory only, used only to read the one file the host selects, and removed on disconnect/restart.
- External services: Google (Drive API, only if enabled). Voice/screen share (not yet implemented) will need a STUN/TURN provider.
