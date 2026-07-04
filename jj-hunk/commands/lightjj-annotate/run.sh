#!/usr/bin/env bash
set -euo pipefail

node - "$@" <<'NODE'
const { spawnSync } = require("child_process");

const args = process.argv.slice(2);
let post = false;
let includeRoutable = false;
let includeAmbiguous = true;
let includeNew = false;
let changeId = "";
let author = "jj-hunk-tool";
let limit = 25;
let addr = "";
let tab = "0";

function usage() {
  console.log(`Usage: gc jj-hunk lightjj-annotate [options]

Preview or post jj-hunk-tool absorb routing as lightjj inline annotations.

Options:
  --post              Write annotations through lightjj api
  --addr HOST:PORT    lightjj address, for example 127.0.0.1:34459
  --tab N             lightjj tab id (default: 0)
  --change ID         lightjj changeId to annotate (default: current focus)
  --author NAME       Annotation author (default: jj-hunk-tool)
  --ambiguous         Include ambiguous hunks (default)
  --routable          Include routable hunks
  --all               Include ambiguous and routable hunks
  --include-new       Include new-file hunks where annotate failed
  --limit N           Maximum annotations to preview/post (default: 25)
  -h, --help          Show this help

Without --post this command prints the annotations it would send.`);
}

for (let i = 0; i < args.length; i++) {
  const arg = args[i];
  if (arg === "--post") post = true;
  else if (arg === "--routable") includeRoutable = true;
  else if (arg === "--ambiguous") includeAmbiguous = true;
  else if (arg === "--all") {
    includeRoutable = true;
    includeAmbiguous = true;
  } else if (arg === "--include-new") includeNew = true;
  else if (arg === "--addr") addr = args[++i] || "";
  else if (arg === "--tab") tab = args[++i] || tab;
  else if (arg === "--change") changeId = args[++i] || "";
  else if (arg === "--author") author = args[++i] || author;
  else if (arg === "--limit") limit = Number(args[++i] || limit);
  else if (arg === "-h" || arg === "--help") {
    usage();
    process.exit(0);
  } else {
    console.error(`unknown argument: ${arg}`);
    usage();
    process.exit(2);
  }
}

if (!Number.isFinite(limit) || limit < 1) {
  console.error("--limit must be a positive number");
  process.exit(2);
}

function run(command, commandArgs) {
  const result = spawnSync(command, commandArgs, {
    encoding: "utf8",
    maxBuffer: 100 * 1024 * 1024,
  });
  return {
    status: result.status ?? 1,
    stdout: result.stdout || "",
    stderr: result.stderr || "",
  };
}

function lightjjArgs(method, path, body) {
  const commandArgs = ["api"];
  if (addr) commandArgs.push("--addr", addr);
  commandArgs.push(method, path);
  if (body !== undefined) commandArgs.push(body);
  return commandArgs;
}

function apiPath(path) {
  return `/tab/${tab}/api/${path.replace(/^\/+/, "")}`;
}

function currentFocusChange() {
  const result = run("lightjj", lightjjArgs("GET", apiPath("focus")));
  if (result.status !== 0) {
    console.error("lightjj is not reachable. Start lightjj in this repo, or pass --change with --post disabled for preview.");
    process.stderr.write(result.stderr || result.stdout);
    process.exit(result.status);
  }
  try {
    const focus = JSON.parse(result.stdout);
    return focus.change_id || focus.changeId || "";
  } catch (err) {
    console.error(`could not parse lightjj focus JSON: ${err.message}`);
    process.exit(1);
  }
}

function parseAbsorbPlan(text) {
  const items = [];
  let section = "";
  for (const line of text.split(/\r?\n/)) {
    if (line.startsWith("Would absorb ")) {
      section = "routable";
      continue;
    }
    if (line.startsWith("Ambiguous ")) {
      section = "ambiguous";
      continue;
    }
    if (!section || !line.startsWith("  ")) continue;

    let match = line.match(/^\s*([0-9a-f]{7}(?:-\d+)?) \((.+) \+(\d+) -(\d+)\) → ([a-z]+) \((.*)\)$/);
    if (match && section === "routable") {
      items.push({
        kind: "routable",
        id: match[1],
        filePath: match[2],
        target: match[5],
        detail: match[6],
      });
      continue;
    }

    match = line.match(/^\s*([0-9a-f]{7}(?:-\d+)?) \((.+) \+(\d+) -(\d+)\) — (.*)$/);
    if (match && section === "ambiguous") {
      items.push({
        kind: "ambiguous",
        id: match[1],
        filePath: match[2],
        detail: match[5],
      });
    }
  }
  return items;
}

function patchAnchor(hunkId, fallbackPath) {
  const patch = run("jj-hunk-tool", ["patch", hunkId]);
  if (patch.status !== 0) {
    return { filePath: fallbackPath, lineNum: 1, lineContent: "" };
  }
  let filePath = fallbackPath;
  let oldLine = 1;
  let newLine = 1;
  let anchor = null;

  for (const line of patch.stdout.split(/\r?\n/)) {
    const file = line.match(/^\+\+\+ b\/(.+)$/);
    if (file) {
      filePath = file[1];
      continue;
    }
    const header = line.match(/^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/);
    if (header) {
      oldLine = Number(header[1]);
      newLine = Number(header[2]);
      continue;
    }
    if (line.startsWith("+++") || line.startsWith("---") || line.startsWith("@@")) continue;
    if (line.startsWith("+") && !anchor) {
      anchor = { lineNum: newLine, side: "new", lineContent: line.slice(1) };
      newLine++;
      continue;
    }
    if (line.startsWith("-")) {
      if (!anchor) anchor = { lineNum: oldLine, side: "old", lineContent: line.slice(1) };
      oldLine++;
      continue;
    }
    if (line.startsWith(" ")) {
      oldLine++;
      newLine++;
    }
  }

  return { filePath, ...(anchor || { lineNum: 0, side: "new", lineContent: "" }) };
}

function commentFor(item) {
  if (item.kind === "routable") {
    return `jj-hunk-tool absorb would route hunk ${item.id} to ${item.target}: ${item.detail}`;
  }
  return `jj-hunk-tool absorb left hunk ${item.id} ambiguous: ${item.detail}`;
}

const absorb = run("jj-hunk-tool", ["absorb", "--dry-run", "--debug"]);
const absorbText = absorb.stdout + absorb.stderr;
if (absorb.status !== 0) {
  process.stderr.write(absorbText);
  process.exit(absorb.status);
}

let plan = parseAbsorbPlan(absorbText).filter((item) => {
  if (item.kind === "routable" && !includeRoutable) return false;
  if (item.kind === "ambiguous" && !includeAmbiguous) return false;
  if (!includeNew && /annotation failed/i.test(item.detail)) return false;
  return true;
});

plan = plan.slice(0, limit);
if (plan.length === 0) {
  console.log("No matching jj-hunk-tool absorb annotations to report.");
  process.exit(0);
}

if (post && !changeId) changeId = currentFocusChange();
if (post && !changeId) {
  console.error("could not determine lightjj changeId; pass --change ID");
  process.exit(1);
}

const annotations = plan.map((item) => {
  const anchor = patchAnchor(item.id, item.filePath);
  return {
    id: `jj-hunk-absorb-${item.id}`,
    changeId,
    filePath: anchor.filePath,
    lineNum: anchor.lineNum,
    side: anchor.side,
    lineContent: anchor.lineContent,
    comment: commentFor(item),
    severity: item.kind === "ambiguous" ? "question" : "suggestion",
    author,
  };
});

if (!post) {
  console.log(`Previewing ${annotations.length} lightjj annotation(s). Re-run with --post to write them.`);
  for (const ann of annotations) {
    console.log(`${ann.id} ${ann.filePath}:${ann.lineNum}:${ann.side} [${ann.severity}] ${ann.comment}`);
  }
  process.exit(0);
}

for (const ann of annotations) {
  const result = run("lightjj", lightjjArgs("POST", apiPath("annotations"), JSON.stringify(ann)));
  if (result.status !== 0) {
    process.stderr.write(result.stderr || result.stdout);
    process.exit(result.status);
  }
  console.log(`posted ${ann.id} ${ann.filePath}:${ann.lineNum}`);
}
NODE
