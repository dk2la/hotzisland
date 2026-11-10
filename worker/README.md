# Pocket trial server

A tiny Cloudflare Worker that remembers when the Trial started on each Mac, so
reinstalling Pocket or deleting its local data does not restart the Trial.

## API

```
POST /trial
Content-Type: application/json

{"macId":"<64 lowercase hex chars>"}
```

`macId` is a SHA-256 hash of the Mac's hardware id. The response is

```json
{"trialStartedAt": 1800000000, "serverTime": 1800086400}
```

(unix seconds). The first call for an unknown `macId` stores the current server
time as `trialStartedAt`; every later call returns the same value. `serverTime`
is the server's clock at the moment of the call.

Everything else is rejected with a small JSON body `{"error":"..."}`:

| Case                               | Status |
| ---------------------------------- | ------ |
| Any path other than `/trial`       | 404    |
| Any method other than `POST`       | 405    |
| Invalid JSON, missing or bad macId | 400    |
| Body larger than 1 KB              | 413    |

## What is stored

Only one KV entry per Mac: key = the hashed Mac ID, value = the Trial start
date in unix seconds. Nothing else: no IP addresses, no headers, no request
logs (`[observability]` is disabled in `wrangler.toml` and the code never
calls `console.log`). The hash cannot be turned back into a hardware id.

## Test

No dependencies needed (Node 22+):

```sh
node --test worker/test.mjs
```

## Deploy

Run from this `worker/` directory. A free Cloudflare account is enough.

```sh
npx wrangler login
npx wrangler kv namespace create TRIALS
```

Paste the printed `id` into `wrangler.toml` in place of
`REPLACE_WITH_KV_NAMESPACE_ID`, then:

```sh
npx wrangler deploy
```

Wrangler prints the Worker URL, e.g.
`https://pocket-trial.<your-subdomain>.workers.dev`.

## Verify

```sh
curl -sS -X POST https://pocket-trial.<your-subdomain>.workers.dev/trial \
  -H 'Content-Type: application/json' \
  -d '{"macId":"0000000000000000000000000000000000000000000000000000000000000000"}'
```

Running it twice must print the same `trialStartedAt`. To remove the test
entry afterwards:

```sh
npx wrangler kv key delete --binding TRIALS --remote \
  0000000000000000000000000000000000000000000000000000000000000000
```

## After deploy

Put the Worker URL (including the `/trial` path if the config expects the full
endpoint) into `Sources/Licensing/LicensingConfig.swift` as `trialServerURL`.

## Notes

- KV is eventually consistent, so two first calls for the same Mac that land
  within the same few seconds may each write a date. They differ by seconds at
  most, and the value settles to a single one.
- To reset the Trial for one Mac (e.g. for testing), delete its key with
  `npx wrangler kv key delete` as shown above.
