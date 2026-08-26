const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");

// Reading the interfaces rather than shelling out to the tailscale binary keeps
// this the same script on macOS and Windows, where that binary lives elsewhere.
function tailnetAddress() {
  for (const addresses of Object.values(os.networkInterfaces())) {
    for (const address of addresses || []) {
      if (address.family !== "IPv4" || address.internal) continue;
      if (isTailnet(address.address)) return address.address;
    }
  }
  throw new Error("no tailnet address on this machine");
}

function isTailnet(address) {
  const parts = String(address).split(".");
  if (parts.length !== 4) return false;
  const numbers = parts.map((part) => (/^\d{1,3}$/.test(part) ? Number(part) : NaN));
  if (numbers.some((value) => Number.isNaN(value) || value > 255)) return false;
  return numbers[0] === 100 && numbers[1] >= 64 && numbers[1] <= 127;
}

// A bind outside the tailnet range would put dsh on whatever LAN the machine
// happens to be on, so refuse rather than guess.
function requireTailnet(address) {
  if (!isTailnet(address)) throw new Error(`refusing to bind ${address}, not a tailnet address`);
  return address;
}

// This proxy speaks to dsh as if it were loopback, which means dsh's own Host
// and Origin checks stop protecting it. That protection has to be replaced here
// rather than merely removed, so every request carries a shared key only this
// machine's owner holds. A browser cannot set the header on a WebSocket at all,
// and cannot set it cross-origin on a fetch without a preflight, which is
// refused below, so the key also covers the DNS rebinding case dsh loses.
const TOKEN_FILE = path.join(os.homedir(), ".dsh", "proxy-token");

function readToken() {
  const fromEnv = (process.env.DSH_PROXY_TOKEN || "").trim();
  if (fromEnv.length >= 32) return fromEnv;
  if (fromEnv) throw new Error("DSH_PROXY_TOKEN is too short to be a key");
  let stat;
  try {
    stat = fs.statSync(TOKEN_FILE);
  } catch {
    throw new Error(
      "no proxy key. Create one with:\n" +
        `  mkdir -p ~/.dsh && openssl rand -hex 32 > ${TOKEN_FILE} && chmod 600 ${TOKEN_FILE}`
    );
  }
  // Windows has no POSIX mode: statSync reports a fabricated 0o666 there, which
  // reads as world readable and would refuse every key on that machine.
  if (process.platform !== "win32" && stat.mode & 0o077) {
    throw new Error(`${TOKEN_FILE} is group or world readable, chmod 600 it`);
  }
  const value = fs.readFileSync(TOKEN_FILE, "utf8").trim();
  if (value.length < 32) throw new Error(`${TOKEN_FILE} is too short to be a key`);
  return value;
}

let TOKEN_BYTES = Buffer.alloc(0);

function presented(request) {
  const header = request.headers["x-dsh-key"];
  if (typeof header === "string" && header) return header;
  // A WebSocket opened by a browser cannot carry a custom header, so the
  // subprotocol slot is the usual place to put one. Native clients use the
  // header; this keeps a browser client possible without weakening anything.
  const proto = request.headers["sec-websocket-protocol"];
  if (typeof proto !== "string") return "";
  const carried = proto
    .split(",")
    .map((part) => part.trim())
    .find((part) => part.startsWith("dsh-key."));
  return carried ? carried.slice("dsh-key.".length) : "";
}

function authorized(request) {
  const supplied = Buffer.from(presented(request));
  if (supplied.length !== TOKEN_BYTES.length) return false;
  return crypto.timingSafeEqual(supplied, TOKEN_BYTES);
}

// Only the RPC surface is forwarded. Everything else dsh serves, the bundled web
// UI and its assets, has no business being reachable from another machine.
function allowedPath(url) {
  return typeof url === "string" && url.startsWith("/api/");
}

const PEERS = (process.env.DSH_PROXY_PEERS || "")
  .split(",")
  .map((part) => part.trim())
  .filter(Boolean);

function peerAllowed(socket) {
  const address = (socket.remoteAddress || "").replace(/^::ffff:/, "");
  if (address === "127.0.0.1" || address === "::1") return true;
  if (!isTailnet(address)) return false;
  return PEERS.length === 0 || PEERS.includes(address);
}

const TARGET_PORT = Number(process.env.DSH_PROXY_TARGET || 3080);
const TARGET_HOST = "127.0.0.1";
const TARGET_AUTHORITY = `${TARGET_HOST}:${TARGET_PORT}`;
const IDLE_MS = Number(process.env.DSH_PROXY_IDLE_MS) || 15 * 60 * 1000;
const VERBOSE = process.env.DSH_PROXY_VERBOSE === "1";

function forwardHeaders(headers) {
  const copy = { ...headers, host: TARGET_AUTHORITY };
  delete copy.origin;
  delete copy["x-dsh-key"];
  return copy;
}

function stamp() {
  return new Date().toISOString();
}

function note(message) {
  console.log(`${stamp()} ${message}`);
}

// The per-request line carries the peer address, so it is off unless someone
// asks for it. Refusals and errors always speak up.
function trace(kind, request) {
  if (!VERBOSE) return;
  console.log(`${stamp()} ${kind} ${request.socket.remoteAddress} ${request.method} ${request.url}`);
}

function admissible(request) {
  return peerAllowed(request.socket) && allowedPath(request.url) && authorized(request);
}

const server = http.createServer((request, response) => {
  trace("http", request);
  // One refusal for every reason, so a peer cannot learn from the answer
  // whether it guessed the path or the key.
  if (request.method === "OPTIONS" || !admissible(request)) {
    note(`refused http ${request.socket.remoteAddress} ${request.method} ${request.url}`);
    request.resume();
    response.writeHead(401, { "content-type": "text/plain" });
    return response.end("unauthorized");
  }
  const upstream = http.request({
    host: TARGET_HOST,
    port: TARGET_PORT,
    path: request.url,
    method: request.method,
    headers: forwardHeaders(request.headers),
    timeout: IDLE_MS,
  });
  upstream.on("response", (upstreamResponse) => {
    upstreamResponse.on("error", (error) => {
      note(`upstream body error ${request.url} ${error.code || error.message}`);
      response.destroy();
    });
    response.writeHead(upstreamResponse.statusCode || 502, upstreamResponse.headers);
    upstreamResponse.pipe(response);
  });
  upstream.on("timeout", () => upstream.destroy(new Error("upstream idle timeout")));
  upstream.on("error", (error) => {
    note(`upstream error ${request.url} ${error.code || error.message}`);
    if (response.headersSent) return response.destroy();
    response.writeHead(502, { "content-type": "text/plain" });
    response.end("dsh unreachable");
  });
  request.on("error", (error) => {
    note(`client error ${request.url} ${error.code || error.message}`);
    upstream.destroy();
  });
  // The request's own 'close' fires as soon as the body has been read, which is
  // before the answer exists; the response's 'close' is the one that means the
  // client actually went away.
  response.on("close", () => {
    if (!response.writableEnded) upstream.destroy();
  });
  request.pipe(upstream);
});

server.on("upgrade", (request, socket, head) => {
  trace("ws", request);
  // The raw socket is live from here on, so it gets its error handler before
  // anything else can throw on it.
  socket.on("error", () => socket.destroy());
  socket.setTimeout(IDLE_MS, () => socket.destroy());
  if (!admissible(request)) {
    note(`refused ws ${socket.remoteAddress} ${request.url}`);
    return socket.end("HTTP/1.1 401 Unauthorized\r\nconnection: close\r\n\r\n");
  }
  const upstream = http.request({
    host: TARGET_HOST,
    port: TARGET_PORT,
    path: request.url,
    method: request.method,
    headers: forwardHeaders(request.headers),
    timeout: IDLE_MS,
  });
  upstream.on("upgrade", (upstreamResponse, upstreamSocket, upstreamHead) => {
    const lines = Object.entries(upstreamResponse.headers).map(([key, value]) => `${key}: ${value}`);
    socket.write(`HTTP/1.1 101 Switching Protocols\r\n${lines.join("\r\n")}\r\n\r\n`);
    if (upstreamHead && upstreamHead.length) socket.unshift(upstreamHead);
    if (head && head.length) upstreamSocket.write(head);
    upstreamSocket.setTimeout(IDLE_MS, () => upstreamSocket.destroy());
    upstreamSocket.pipe(socket);
    socket.pipe(upstreamSocket);
    upstreamSocket.on("error", () => socket.destroy());
    socket.on("error", () => upstreamSocket.destroy());
    socket.on("close", () => upstreamSocket.destroy());
  });
  // dsh answering an upgrade with an ordinary response means it is restarting or
  // refusing the path. With no listener that reply is never consumed and the
  // client socket stays open until the process dies.
  upstream.on("response", (upstreamResponse) => {
    note(`upgrade refused upstream ${request.url} ${upstreamResponse.statusCode}`);
    upstreamResponse.resume();
    socket.destroy();
  });
  upstream.on("timeout", () => upstream.destroy(new Error("upstream idle timeout")));
  upstream.on("error", (error) => {
    note(`upstream ws error ${request.url} ${error.code || error.message}`);
    socket.destroy();
  });
  socket.on("close", () => upstream.destroy());
  upstream.end();
});

server.on("clientError", (error, socket) => {
  note(`client protocol error ${error.code || error.message}`);
  if (socket.writable) socket.end("HTTP/1.1 400 Bad Request\r\nconnection: close\r\n\r\n");
  socket.destroy();
});

server.on("error", (error) => {
  console.error(`${stamp()} proxy server error ${error.code || error.message}`);
  process.exitCode = 1;
  server.close();
});

// A thrown handler must not take the tunnel down with it; the line above is the
// only record anyone gets, so it keeps the stack.
process.on("uncaughtException", (error) => {
  console.error(`${stamp()} uncaught ${error && error.stack ? error.stack : error}`);
});

function main() {
  TOKEN_BYTES = Buffer.from(readToken());
  const port = Number(process.env.DSH_PROXY_PORT || 3080);
  const host = requireTailnet(process.env.DSH_PROXY_BIND || tailnetAddress());
  server.listen(port, host, () => {
    note(`dsh tailnet proxy on ${host}:${port} to ${TARGET_AUTHORITY}, key required`);
  });
}

if (require.main === module) main();

// The pure halves are exported so they can be tested without binding a socket
// or holding the real key.
module.exports = { isTailnet, allowedPath, peerAllowed, presented, forwardHeaders, main };
