#!/usr/bin/env node
// A tiny static file server for the QuranTathbit web build, with zero
// dependencies beyond Node itself. Run via `npx qurantathbit` (after a global
// or npx install) or `npm install qurantathbit && node node_modules/qurantathbit/start.js`.
//
// Serves the same files GitHub Pages serves -- index.html, the .wasm and .js
// the engine loads, the .pck with the deck, and the decks/quran/ folder the
// recitations stream from -- so a person who installs the package gets the
// whole app at http://localhost:8080 with nothing else to set up.

const http = require("http");
const fs = require("fs");
const path = require("path");

const ROOT = __dirname;
const PORT = parseInt(process.env.PORT || "8080", 10);
const HOST = process.env.HOST || "127.0.0.1";

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".wasm": "application/wasm",
  ".pck": "application/octet-stream",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".json": "application/json; charset=utf-8",
  ".mp3": "audio/mpeg",
  ".ogg": "audio/ogg",
  ".wav": "audio/wav",
  ".m4a": "audio/mp4",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".otf": "font/otf",
  ".ico": "image/x-icon",
  ".txt": "text/plain; charset=utf-8",
  ".md": "text/markdown; charset=utf-8",
};

function safeJoin(root, target) {
  // path.join alone collapses "../" before the join, so a request like
  // /../../etc/passwd would resolve outside the web root. Resolve against
  // root and confirm the result is still inside root.
  const resolved = path.resolve(root, "." + target);
  if (resolved !== root && !resolved.startsWith(root + path.sep)) {
    return null;
  }
  return resolved;
}

function serve(req, res) {
  const url = new URL(req.url, "http://" + HOST);
  let pathname = url.pathname;
  if (pathname === "/") pathname = "/index.html";

  const filePath = safeJoin(ROOT, pathname.split("/").map(decodeURIComponent).join("/"));
  if (!filePath) {
    res.writeHead(403, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("403 forbidden");
    return;
  }

  fs.stat(filePath, (err, stat) => {
    if (err || !stat.isFile()) {
      res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
      res.end("404 not found");
      return;
    }
    const ext = path.extname(filePath).toLowerCase();
    const type = TYPES[ext] || "application/octet-stream";
    // The web build's audio and wasm are loaded with range requests in some
    // browsers; honour them so streaming works.
    const range = req.headers.range;
    if (range) {
      const total = stat.size;
      const m = /bytes=(\d*)-(\d*)/.exec(range);
      if (m) {
        const start = m[1] ? parseInt(m[1], 10) : 0;
        const end = m[2] ? parseInt(m[2], 10) : total - 1;
        if (start <= end && end < total) {
          res.writeHead(206, {
            "Content-Type": type,
            "Content-Range": `bytes ${start}-${end}/${total}`,
            "Accept-Ranges": "bytes",
            "Content-Length": end - start + 1,
          });
          fs.createReadStream(filePath, { start, end }).pipe(res);
          return;
        }
      }
    }
    res.writeHead(200, {
      "Content-Type": type,
      "Content-Length": stat.size,
      "Cache-Control": "no-cache",
    });
    fs.createReadStream(filePath).pipe(res);
  });
}

const server = http.createServer(serve);
server.listen(PORT, HOST, () => {
  console.log("QuranTathbit");
  console.log("  serving " + ROOT);
  console.log("  open    http://" + HOST + ":" + PORT + "/");
  console.log("  Ctrl-C to stop");
});
