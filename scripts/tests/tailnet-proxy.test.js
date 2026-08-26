const assert = require("node:assert");
const { test } = require("node:test");
const proxy = require("../tailnet-proxy.js");

test("isTailnet accepts the CGNAT range and nothing else", () => {
  for (const address of ["100.64.0.1", "100.100.100.100", "100.127.255.254"]) {
    assert.equal(proxy.isTailnet(address), true, address);
  }
  for (const address of ["100.63.255.255", "100.128.0.1", "10.0.0.1", "8.8.8.8"]) {
    assert.equal(proxy.isTailnet(address), false, address);
  }
});

test("isTailnet rejects malformed input rather than coercing it", () => {
  for (const address of ["100.64.abc.1", "100.100.1.1.evil", "100.64.1", "100.999.1.1", "", "100.64.01.1.1"]) {
    assert.equal(proxy.isTailnet(address), false, address);
  }
});

test("only the api surface is forwarded", () => {
  assert.equal(proxy.allowedPath("/api/session.list"), true);
  assert.equal(proxy.allowedPath("/index.html"), false);
  assert.equal(proxy.allowedPath("/"), false);
  assert.equal(proxy.allowedPath(undefined), false);
});

test("the key is read from the header or the websocket subprotocol", () => {
  assert.equal(proxy.presented({ headers: { "x-dsh-key": "abc" } }), "abc");
  assert.equal(
    proxy.presented({ headers: { "sec-websocket-protocol": "chat, dsh-key.abc" } }),
    "abc"
  );
  assert.equal(proxy.presented({ headers: {} }), "");
});

test("the caller's key never reaches dsh, and neither does its Origin", () => {
  const forwarded = proxy.forwardHeaders({
    host: "100.100.100.100:3080",
    origin: "http://evil.example",
    "x-dsh-key": "secret",
    "content-type": "application/json",
  });
  assert.equal(forwarded.host, "127.0.0.1:3080");
  assert.equal(forwarded.origin, undefined);
  assert.equal(forwarded["x-dsh-key"], undefined);
  assert.equal(forwarded["content-type"], "application/json");
});

test("peers outside the tailnet are refused, loopback is not", () => {
  assert.equal(proxy.peerAllowed({ remoteAddress: "127.0.0.1" }), true);
  assert.equal(proxy.peerAllowed({ remoteAddress: "::ffff:100.100.100.100" }), true);
  assert.equal(proxy.peerAllowed({ remoteAddress: "8.8.8.8" }), false);
  assert.equal(proxy.peerAllowed({ remoteAddress: "" }), false);
});
