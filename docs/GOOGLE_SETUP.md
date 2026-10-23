# Google setup: "Continue with Google" and Google Drive

One Google OAuth client serves both features. You need your public server address first (see DEPLOYMENT.md).
Below, replace `YOUR_DOMAIN` with it, e.g. `party.example.com`.

## 1. Create the project and enable Drive
1. Open https://console.cloud.google.com and sign in. Create a project (top bar -> New project -> name it Orvella).
2. Menu -> **APIs & Services -> Library**, search **Google Drive API**, click **Enable**.

## 2. Set up the consent screen
Google has been renaming these pages ("Google Auth Platform": Branding, Audience, Data Access, Clients). Names may differ slightly.
1. **OAuth consent screen / Branding:** app name `Orvella`, your email as support and developer contact.
2. **Audience:** choose **External**. Leave the publishing status as **Testing**.
3. **Test users:** click Add users and add the Gmail address of **every person who will use Google sign-in or Drive** (you and each friend, up to 100). People not listed are blocked.
4. **Data access / Scopes:** add `openid`, `email`, `profile`, and `https://www.googleapis.com/auth/drive.readonly`.

## 3. Create the credentials
1. **Credentials -> Create credentials -> OAuth client ID** (or Clients -> Create client).
2. Application type: **Web application**. Name: `Orvella server`.
3. **Authorized redirect URIs** - add BOTH, exactly (https, no trailing slash):
   - `https://YOUR_DOMAIN/auth/google/callback`
   - `https://YOUR_DOMAIN/drive/oauth/callback`
4. Create. Copy the **Client ID** and **Client secret**. The secret is a password: never put it in GitHub or the app.

## 4. Give them to the server
- First-time setup: the `setup-server.sh` script asks for them.
- Already set up: on the server edit `/opt/orvella/deploy/.env`, set `GOOGLE_OAUTH_CLIENT_ID=` and `GOOGLE_OAUTH_CLIENT_SECRET=`, then run `cd /opt/orvella/deploy && docker compose up -d`.

## 5. What users see
- **Continue with Google** (welcome/log-in screens): opens the browser, the user picks their Google account, then Orvella signs them in. Accounts are matched by verified email.
- **Google Drive** (inside a party, host only): *Choose what to watch -> Google Drive -> Connect Google Drive*. Google shows
  "Google hasn't verified this app" while in Testing: click **Advanced -> Go to Orvella (unsafe)**, then allow read-only access.
  The host then browses folders and picks a video. Friends in the party stream that one file; they never get access to your Drive.

## Limits to know
- In **Testing** mode Google expires Drive authorization after **7 days**: the host just taps *Connect Google Drive* again.
- Opening this to the public needs Google's verification; `drive.readonly` is a restricted scope, which can require a paid security assessment. For you and friends, Testing mode is the practical choice.
- Files must be real video files (mp4, mkv, webm...). Google Docs/Sheets are not listed.
- If connecting fails with `redirect_uri_mismatch`, the URI in step 3 does not exactly match `PUBLIC_URL`.
