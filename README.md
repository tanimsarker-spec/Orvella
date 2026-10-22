# Orvella
Watch-together cinema app for Windows, Android and iOS.

## Status (honest)
| Area | State |
|---|---|
| Server: accounts, rooms, WebSocket sync, media relay, Drive proxy, rate limits | Implemented, 17 automated tests pass |
| Flutter app: all 10 screens, sync, player, PC-file hosting, Drive browser, chat | Implemented, **not yet compiled or run on any device** |
| Voice chat | Not implemented (server relays WebRTC signaling only) |
| Screen sharing | Not implemented |
| Database + migrations | Not implemented (server state is in memory) |
| iOS real-device/TestFlight signing | Not set up (CI builds unsigned only) |
| 4K / high-bitrate validation | Not done; needs real-world measurement |

A platform is "working" only when its CI job is green AND you have tested it on a device.

## Run the server locally
`cd server && npm install && npm test && npm start`

## Deploy / Google Drive / build variables
See `docs/DEPLOYMENT.md`.
