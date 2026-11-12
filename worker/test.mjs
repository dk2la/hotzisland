// Run with: node --test worker/test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./src/index.js";

const MAC_A = "a".repeat(64);
const MAC_B = "0123456789abcdef".repeat(4);

// In-memory stand-in for a Workers KV namespace.
function makeEnv() {
  const store = new Map();
  return {
    store,
    TRIALS: {
      async get(key) {
        return store.has(key) ? store.get(key) : null;
      },
      async put(key, value) {
        store.set(key, value);
      },
    },
  };
}

function post(body, { path = "/trial", headers = {} } = {}) {
  return new Request(`https://trial.example${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function expectError(response, status) {
  assert.equal(response.status, status);
  assert.match(response.headers.get("content-type"), /application\/json/);
  const payload = await response.json();
  assert.equal(typeof payload.error, "string");
  assert.deepEqual(Object.keys(payload), ["error"]);
}

test("first call creates the trial with the current server time", async () => {
  const env = makeEnv();
  const before = Math.floor(Date.now() / 1000);
  const response = await worker.fetch(post({ macId: MAC_A }), env);
  const after = Math.floor(Date.now() / 1000);

  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type"), /application\/json/);
  const payload = await response.json();
  assert.deepEqual(Object.keys(payload), ["trialStartedAt", "serverTime"]);
  assert.ok(payload.serverTime >= payload.trialStartedAt);
  assert.ok(Number.isInteger(payload.trialStartedAt));
  assert.ok(payload.trialStartedAt >= before && payload.trialStartedAt <= after);
});

test("repeat call returns the same date", async (t) => {
  const env = makeEnv();
  t.mock.timers.enable({ apis: ["Date"], now: 1_800_000_000_000 });

  const first = await (await worker.fetch(post({ macId: MAC_A }), env)).json();
  assert.equal(first.trialStartedAt, 1_800_000_000);

  t.mock.timers.setTime(1_800_000_000_000 + 5 * 24 * 3600 * 1000);
  const second = await (await worker.fetch(post({ macId: MAC_A }), env)).json();
  assert.equal(second.trialStartedAt, 1_800_000_000);
  assert.equal(env.store.get(MAC_A), "1800000000");
});

test("different macIds are independent", async (t) => {
  const env = makeEnv();
  t.mock.timers.enable({ apis: ["Date"], now: 1_800_000_000_000 });
  const a = await (await worker.fetch(post({ macId: MAC_A }), env)).json();

  t.mock.timers.setTime(1_800_000_100_000);
  const b = await (await worker.fetch(post({ macId: MAC_B }), env)).json();
  const aAgain = await (await worker.fetch(post({ macId: MAC_A }), env)).json();

  assert.equal(a.trialStartedAt, 1_800_000_000);
  assert.equal(b.trialStartedAt, 1_800_000_100);
  assert.equal(aAgain.trialStartedAt, 1_800_000_000);
});

test("only the macId key with the date value ends up in KV", async (t) => {
  const env = makeEnv();
  t.mock.timers.enable({ apis: ["Date"], now: 1_800_000_000_000 });
  const request = post(
    { macId: MAC_A, extra: "ignored" },
    { headers: { "CF-Connecting-IP": "203.0.113.7", "User-Agent": "Pocket/1.0" } },
  );
  await worker.fetch(request, env);
  await worker.fetch(post({ macId: MAC_A }), env);

  assert.deepEqual([...env.store.entries()], [[MAC_A, "1800000000"]]);
});

test("wrong method is rejected with 405", async () => {
  const env = makeEnv();
  for (const method of ["GET", "PUT", "DELETE"]) {
    const request = new Request("https://trial.example/trial", { method });
    await expectError(await worker.fetch(request, env), 405);
  }
  assert.equal(env.store.size, 0);
});

test("wrong path is rejected with 404", async () => {
  const env = makeEnv();
  for (const path of ["/", "/trial/", "/trials", "/trial/x"]) {
    await expectError(await worker.fetch(post({ macId: MAC_A }, { path }), env), 404);
  }
  assert.equal(env.store.size, 0);
});

test("bad JSON is rejected with 400", async () => {
  const env = makeEnv();
  for (const body of ["", "not json", "{", `macId=${MAC_A}`]) {
    await expectError(await worker.fetch(post(body), env), 400);
  }
  assert.equal(env.store.size, 0);
});

test("missing or malformed macId is rejected with 400", async () => {
  const env = makeEnv();
  const bodies = [
    {},
    null,
    [],
    [MAC_A],
    "just a string",
    { macId: null },
    { macId: 42 },
    { macId: "" },
    { macId: "a".repeat(63) },
    { macId: "a".repeat(65) },
    { macId: "A".repeat(64) },
    { macId: "g".repeat(64) },
    { macId: `${"a".repeat(63)}\n` },
    { macId: [MAC_A] },
  ];
  for (const body of bodies) {
    await expectError(await worker.fetch(post(body), env), 400);
  }
  assert.equal(env.store.size, 0);
});

test("oversized body is rejected with 413", async () => {
  const env = makeEnv();
  const big = JSON.stringify({ macId: MAC_A, padding: "x".repeat(2000) });

  // Declared via Content-Length.
  const declared = post(big, { headers: { "Content-Length": String(big.length) } });
  await expectError(await worker.fetch(declared, env), 413);

  // Streamed without a Content-Length header.
  const stream = new ReadableStream({
    start(controller) {
      controller.enqueue(new TextEncoder().encode(big));
      controller.close();
    },
  });
  const streamed = new Request("https://trial.example/trial", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: stream,
    duplex: "half",
  });
  await expectError(await worker.fetch(streamed, env), 413);

  assert.equal(env.store.size, 0);
});

test("corrupt stored value is replaced by a fresh date", async (t) => {
  const env = makeEnv();
  env.store.set(MAC_A, "garbage");
  t.mock.timers.enable({ apis: ["Date"], now: 1_800_000_000_000 });

  const payload = await (await worker.fetch(post({ macId: MAC_A }), env)).json();
  assert.equal(payload.trialStartedAt, 1_800_000_000);
  assert.equal(env.store.get(MAC_A), "1800000000");
});
