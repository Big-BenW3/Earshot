# Earshot

**An audio shelf for small communities.**

Church sermons, lecture recordings, community podcasts and meetup talks. A host creates a show and uploads recordings. Listeners press play in the browser or subscribe in any podcast app.

Files are stored on [Walrus](https://walrus.xyz) through [Dartus](https://pub.dev/packages/dartus),
the Dart SDK for Walrus. Each host's own Sui wallet (for example [Slush](https://slush.app))
pays for what they store and owns the Blob object on Sui. The server holds no keys and pays for
nothing.

## Features

- **Shows.** A host signs in with a Sui wallet and creates a show with cover art, description, language and category. Each show gets a public page and a podcast feed.
- **Episodes.** MP3, M4A/AAC, OGG or WAV up to 100 MB, with title, description and publish date (future dates schedule the episode). Upload progress is shown throughout.
- **Listening.** A persistent player bar keeps playing across pages, with seek, 15-second skips, playback speed and resume positions. Episodes can be downloaded.
- **Podcast feed.** `/feed/<show>.xml` is RSS 2.0 with iTunes tags, pointing straight at the files on Walrus.
- **Admin.** Edit, hide, pin and reorder episodes, and edit the show.

## How it works

- **`app/`**: Flutter web app. Uploads go through Dartus `WalrusWriter`: the blob ID is computed
  in a Web Worker, the wallet approves the storage payment, the bytes go to the Walrus upload
  relay, and the wallet approves once more to certify. Reads use Dartus `WalrusClient`.
- **`server/`**: Dart ([shelf](https://pub.dev/packages/shelf)) server. Serves the landing page
  and the web app, handles Sign in with Sui, keeps metadata in SQLite, and checks every upload
  on Sui (a certified Walrus Blob owned by the signed-in address) before listing it.
- **`packages/`**: shared packages for wallet connection, sign-in, blob checks and upload
  recovery.

```
landing/    landing page, served at /
app/        Flutter web app, served at /app
server/     Dart server and API
packages/   shared Dart packages
Dockerfile  one image with the app and the server
```

## Running locally

With Docker:

```sh
docker build -t earshot .
docker run -p 8095:8095 -v earshot-data:/data -e PUBLIC_BASE_URL=http://localhost:8095 earshot
```

Or with Flutter 3.44.2:

```sh
cd app && flutter pub get
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run
cd ../server && dart pub get
WEB_DIR=../app/build/web PORT=8095 PUBLIC_BASE_URL=http://localhost:8095 dart run bin/server.dart
```

Open http://localhost:8095 for the landing page and http://localhost:8095/app for the app.
Sign-in is bound to `PUBLIC_BASE_URL`, so open exactly that address (`127.0.0.1` is a different
origin). By default everything runs on Sui testnet.

## Configuration

Environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `PORT` | `8095` | HTTP port |
| `PUBLIC_BASE_URL` | `http://localhost:<PORT>` | The exact URL people open. Sign-in messages are bound to it, and share links and link previews are built from it. Set it in production. |
| `SUI_CHAIN` | `testnet` | `testnet` or `mainnet` |
| `AGGREGATOR_URL` | `https://aggregator.walrus-testnet.walrus.space` (set it for mainnet) | Walrus aggregator for reads |
| `EPOCHS` | `26` | Storage period the app suggests (a mainnet epoch is two weeks). Users pay for what they choose. |
| `MAX_UPLOAD_MB` | `100` | Largest file accepted |
| `DATA_DIR` | `data` | Folder for the SQLite database |
| `TRUST_PROXY` | `false` | Set to `true` behind a reverse proxy that sets `X-Forwarded-*` headers |
| `CLAIM_LIMIT` | `30` | Blob claims one address may make per ten minutes |

## Deploying

The `Dockerfile` builds the web app and the server into one small image. Run it on any host that
supports Docker and give it a persistent volume at `/data`. For mainnet:

```sh
PUBLIC_BASE_URL=https://earshot.example.com
SUI_CHAIN=mainnet
AGGREGATOR_URL=https://aggregator.walrus-mainnet.walrus.space
TRUST_PROXY=true   # when behind the host's proxy
```

There is no publisher to run and no wallet to fund: every upload is paid for by the user's
wallet.

## Licence

MIT. See [LICENSE](LICENSE).
