#!/usr/bin/env node
// Find, and optionally repair, a dsh session log the server cannot read.
//
// A log is a run of independent Zstandard frames: the first holds the header
// line and nothing else, the rest hold whole JSONL lines. session.list builds
// every row by reading these files, so a single bad one takes the whole list
// down and the app comes up with no conversations at all.
//
//   node scripts/session-log-doctor.mjs                     scan the default store
//   node scripts/session-log-doctor.mjs <store>             scan somewhere else
//   node scripts/session-log-doctor.mjs <log> --repair      rewrite one log
//
// The repair only re-frames: every record is decoded, checked and written back
// byte for byte, and the original is kept beside it. A log whose records do not
// parse is left alone, because reframing damage keeps the damage.
import { copyFileSync, existsSync, readdirSync, readFileSync, renameSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { zstdCompressSync, zstdDecompressSync } from "node:zlib";

const MAGIC = Buffer.from([0x28, 0xb5, 0x2f, 0xfd]);

function frameStarts(buffer) {
  const starts = [];
  let at = buffer.indexOf(MAGIC, 0);
  while (at !== -1) {
    starts.push(at);
    at = buffer.indexOf(MAGIC, at + 4);
  }
  return starts;
}

function diagnose(data) {
  if (data.length === 0) return "the file is empty";
  const starts = frameStarts(data);
  if (starts.length === 0 || starts[0] !== 0) return "there is no Zstandard frame at byte 0";
  const end = starts.length > 1 ? starts[1] : data.length;
  let head;
  try {
    head = zstdDecompressSync(data.subarray(0, end));
  } catch (error) {
    return `the first frame will not decode: ${error.message}`;
  }
  if (head.length === 0 || head.indexOf(10) !== head.length - 1) {
    return `the first frame holds ${head.length} bytes rather than one header line`;
  }
  return undefined;
}

function scan(root) {
  const bad = [];
  for (const project of readdirSync(root)) {
    const projectPath = join(root, project);
    if (!statSync(projectPath).isDirectory()) continue;
    for (const session of readdirSync(projectPath)) {
      const file = join(projectPath, session, "session.jsonl.zstd");
      let data;
      try {
        data = readFileSync(file);
      } catch {
        continue;
      }
      const why = diagnose(data);
      if (why) bad.push({ file, why, modified: statSync(file).mtime.toISOString() });
    }
  }
  console.log(`${bad.length} unreadable log(s)`);
  for (const entry of bad) console.log(`${entry.file}\n  ${entry.why}\n  last written ${entry.modified}`);
  return bad.length === 0 ? 0 : 1;
}

function repair(file) {
  const data = readFileSync(file);
  const starts = frameStarts(data);
  console.log(`on disk: ${data.length} bytes in ${starts.length} frame(s)`);
  if (starts.length !== 1 || starts[0] !== 0) throw new Error("this repair only handles a log written as one single frame");

  const plain = zstdDecompressSync(data);
  if (plain[plain.length - 1] !== 10) throw new Error("the log does not end on a newline, so its tail is torn rather than misframed");
  const lines = plain.toString("utf8").split("\n");
  lines.pop();
  for (const [index, line] of lines.entries()) {
    try {
      JSON.parse(line);
    } catch {
      throw new Error(`record ${index} does not parse, so the damage is in the records themselves`);
    }
  }
  console.log(`${lines.length} records, all of them readable`);

  const split = plain.indexOf(10);
  const rebuilt = Buffer.concat([
    zstdCompressSync(plain.subarray(0, split + 1)),
    zstdCompressSync(plain.subarray(split + 1)),
  ]);
  if (diagnose(rebuilt) !== undefined) throw new Error("the rebuilt log still reads as damaged");
  const check = frameStarts(rebuilt);
  const roundTrip = Buffer.concat(check.map((start, index) =>
    zstdDecompressSync(rebuilt.subarray(start, check[index + 1] ?? rebuilt.length))));
  if (!roundTrip.equals(plain)) throw new Error("the rebuilt log does not decode back to the same bytes");

  const backup = `${file}.corrupt-backup`;
  if (existsSync(backup)) throw new Error(`${backup} is already there, so an earlier repair would be overwritten`);
  copyFileSync(file, backup);
  const tmp = `${file}.repair.tmp`;
  writeFileSync(tmp, rebuilt);
  renameSync(tmp, file);
  console.log(`repaired into ${check.length} frames. the original is at ${backup}`);
  return 0;
}

const args = process.argv.slice(2);
const wantsRepair = args.includes("--repair");
const target = args.find((arg) => !arg.startsWith("--")) ?? join(homedir(), ".dsh", "sessions");
// Stop the dsh server before repairing; it holds this file open to append to it.
process.exit(wantsRepair ? repair(target) : scan(target));
