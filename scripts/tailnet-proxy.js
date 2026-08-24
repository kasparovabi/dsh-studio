const http = require("http");
const os = require("os");

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
  const parts = address.split(".").map(Number);
  return parts.length === 4 && parts[0] === 100 && parts[1] >= 64 && parts[1] <= 127;
}

// A bind outside the tailnet range would put dsh on whatever LAN the machine
// happens to be on, so refuse rather than guess.
function requireTailnet(address) {
  if (!isTailnet(address)) throw new Error(`refusing to bind ${address}, not a tailnet address`);
  return address;
}

const LISTEN_PORT = Number(process.env.DSH_PROXY_PORT || 3080);
const LISTEN_HOST = requireTailnet(process.env.DSH_PROXY_BIND || tailnetAddress());
const TARGET_PORT = Number(process.env.DSH_PROXY_TARGET || 3080);
const TARGET_HOST = "127.0.0.1";
const TARGET_AUTHORITY = `${TARGET_HOST}:${TARGET_PORT}`;

// dsh refuses any request whose Host header is not loopback, which is what keeps
// it off the network. Rewriting the header here is the whole job of this proxy;
// the socket itself is still bound to the tailnet address only, so the reachable
// set stays the machines on the tailnet.
function forwardHeaders(headers) {
  const copy = { ...headers, host: TARGET_AUTHORITY };
  delete copy.origin;
  return copy;
}

function trace(kind, request) {
  console.log(`${new Date().toISOString()} ${kind} ${request.socket.remoteAddress} ${request.method} ${request.url}`);
}

const server = http.createServer((request, response) => {
  trace("http", request);
  const upstream = http.request(
    {
      host: TARGET_HOST,
      port: TARGET_PORT,
      path: request.url,
      method: request.method,
      headers: forwardHeaders(request.headers),
    },
    (upstreamResponse) => {
      response.writeHead(upstreamResponse.statusCode || 502, upstreamResponse.headers);
      upstreamResponse.pipe(response);
    }
  );
  upstream.on("error", () => {
    response.writeHead(502);
    response.end("dsh unreachable");
  });
  request.pipe(upstream);
});

server.on("upgrade", (request, socket, head) => {
  trace("ws", request);
  const upstream = http.request({
    host: TARGET_HOST,
    port: TARGET_PORT,
    path: request.url,
    method: request.method,
    headers: forwardHeaders(request.headers),
  });
  upstream.on("upgrade", (upstreamResponse, upstreamSocket, upstreamHead) => {
    const lines = Object.entries(upstreamResponse.headers).map(([key, value]) => `${key}: ${value}`);
    socket.write(`HTTP/1.1 101 Switching Protocols\r\n${lines.join("\r\n")}\r\n\r\n`);
    if (upstreamHead && upstreamHead.length) socket.unshift(upstreamHead);
    if (head && head.length) upstreamSocket.write(head);
    upstreamSocket.pipe(socket);
    socket.pipe(upstreamSocket);
    upstreamSocket.on("error", () => socket.destroy());
    socket.on("error", () => upstreamSocket.destroy());
  });
  upstream.on("error", () => socket.destroy());
  upstream.end();
});

server.listen(LISTEN_PORT, LISTEN_HOST, () => {
  console.log(`dsh tailnet proxy on ${LISTEN_HOST}:${LISTEN_PORT} to ${TARGET_AUTHORITY}`);
});
