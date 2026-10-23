# Deploying Orvella (real server, no tunnels)

Friends and the host connect OUT to your server over HTTPS, so nobody opens ports or uses a VPN.
Video from a host's PC or Google Drive passes through this server, so choose a plan with plenty of bandwidth.

## 1. Rent a small server
Any small Linux VPS works (1-2 vCPU, 1-4 GB RAM, Ubuntu 24.04). Pick a data centre near your friends.
Check the provider's *included monthly traffic*: each viewer pulls roughly the video's bitrate from the server
(1080p ~ 4 GB/hour per viewer, 4K ~ 20 GB/hour per viewer).
Add your SSH public key when creating it (see step 4).

## 2. Get a domain name pointing at it
Buy a domain, or use a free dynamic-DNS subdomain. Create an **A record** for e.g. `party.yourdomain.com`
pointing to the server's IP address. HTTPS certificates are fetched automatically (Caddy) once DNS works.

## 3. Run the one-time setup on the server
SSH in as root, copy `deploy/setup-server.sh` onto the server, and run `sudo bash setup-server.sh`.
It asks for your domain (and optionally Google credentials), installs Docker, opens only ports 22/80/443,
and creates a random JWT secret. Re-running it is safe.

## 4. Let GitHub deploy for you
On your PC (PowerShell): `ssh-keygen -t ed25519 -f orvella_deploy -N '""'`
- Put `orvella_deploy.pub` in the server's `/root/.ssh/authorized_keys` (or paste it into the provider's SSH key box).
- In GitHub: Settings -> Secrets and variables -> Actions -> **Secrets**:
  `DEPLOY_HOST` (server IP or domain), `DEPLOY_SSH_KEY` (full contents of the private file `orvella_deploy`),
  optionally `DEPLOY_USER` (default `root`). Never commit the private key.
- **Variables**: `ORVELLA_SERVER` = `https://party.yourdomain.com`. Optional `DEPLOY_ENABLED` = `true` to
  auto-deploy on every push to `server/`.
- Actions -> **Deploy server** -> Run workflow. It ends with "Server is live".

## 5. Build the apps
Re-run the **CI** workflow. Apps now have your server address built in; users just sign up and tap.

## 6. Google sign-in and Google Drive (optional)
See **GOOGLE_SETUP.md** (one client covers both).

## 6b. Old note on Google Drive
Google Cloud Console: enable Drive API; OAuth consent screen = External, add Test users; create an OAuth
client of type **Web application** with redirect URI `https://party.yourdomain.com/drive/oauth/callback`.
`drive.readonly` is a restricted scope: in Testing mode only listed test users work and access expires after 7 days;
public release needs Google verification. Put the client ID/secret in the setup script (or edit `/opt/orvella/deploy/.env`
on the server, then `docker compose up -d`).

## 7. Email (password reset) and voice chat
- **Email:** the setup script asks for SMTP details. Any SMTP provider works (Gmail needs an *app password*).
  Without SMTP, "Forgot password" answers that email is unavailable.
- **Voice chat** uses a TURN relay (coturn) that the setup script and compose file already include. It needs ports
  3478 (tcp+udp) and 49160-49200 (udp) open: the script opens them in the server firewall; also open them in your
  provider's cloud firewall panel if it has one.

## 8. Operations
- Accounts live in a SQLite file in the Docker volume `orvella_data`. Back it up:
  `docker run --rm -v deploy_orvella_data:/d -v $PWD:/b alpine tar czf /b/orvella-data.tgz -C /d .`
- Logs: `cd /opt/orvella/deploy && docker compose logs -f`
- Rooms are held in memory: restarting the server ends active parties (accounts are kept).

## Data handling
Stored: email, display name, salted password hash. Not stored: chat, video, Google tokens (memory only, removed on
disconnect/restart). External service: Google (Drive API) only if enabled.
