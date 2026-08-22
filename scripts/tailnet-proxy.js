const http = require("http");
const { execFileSync } = require("child_process");

function tailnetAddress() {
  for (const binary of ["/usr/local/bin/tailscale", "/Applications/Tailscale.app/Contents/MacOS/Tailscale"]) {
    try {
      return execFileSync(binary, ["ip", "-4"], { encoding: "utf8" }).trim().split("\n")[0];
    } catch {
      continue;
    }
  }
  throw new Error("tailscale address not found");
}

const LISTEN_PORT = Number(process.env.DSH_PROXY_PORT || 3080);
const LISTEN_HOST = process.env.DSH_PROXY_BIND || tailnetAddress();
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

const server = http.createServer((request, response) => {
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
