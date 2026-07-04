#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const ACTIVE_STATUSES = new Set(["open", "in_progress", "blocked", "deferred"]);
const ROOT_TYPES = new Set(["task", "bug", "feature", "chore"]);
const DEFAULT_SCHEMA = "gc.reports.root-task-stage.v1";
const DEFAULT_DOCUMENT = "root-task-stage-report";

function parseArgs(argv) {
  const opts = {
    output: "",
    manifest: "",
    rigs: "",
    includeWisps: false,
    includeWorkflowMetadata: false,
    cityRoot: "",
    docsWorkspace: "default",
    docsWorkspacePath: "",
    docsArtifactRoot: "",
    documentName: DEFAULT_DOCUMENT,
    documentSchema: DEFAULT_SCHEMA,
    format: "markdown",
  };

  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--include-wisps") {
      opts.includeWisps = true;
    } else if (arg === "--include-workflow-metadata") {
      opts.includeWorkflowMetadata = true;
    } else if (arg === "--output") {
      opts.output = argv[++i] || "";
    } else if (arg.startsWith("--output=")) {
      opts.output = arg.slice("--output=".length);
    } else if (arg === "--manifest") {
      opts.manifest = argv[++i] || "";
    } else if (arg.startsWith("--manifest=")) {
      opts.manifest = arg.slice("--manifest=".length);
    } else if (arg === "--rigs") {
      opts.rigs = argv[++i] || "";
    } else if (arg.startsWith("--rigs=")) {
      opts.rigs = arg.slice("--rigs=".length);
    } else if (arg === "--city-root") {
      opts.cityRoot = argv[++i] || "";
    } else if (arg.startsWith("--city-root=")) {
      opts.cityRoot = arg.slice("--city-root=".length);
    } else if (arg === "--docs-workspace") {
      opts.docsWorkspace = argv[++i] || opts.docsWorkspace;
    } else if (arg.startsWith("--docs-workspace=")) {
      opts.docsWorkspace = arg.slice("--docs-workspace=".length);
    } else if (arg === "--docs-workspace-path") {
      opts.docsWorkspacePath = argv[++i] || "";
    } else if (arg.startsWith("--docs-workspace-path=")) {
      opts.docsWorkspacePath = arg.slice("--docs-workspace-path=".length);
    } else if (arg === "--docs-artifact-root") {
      opts.docsArtifactRoot = argv[++i] || "";
    } else if (arg.startsWith("--docs-artifact-root=")) {
      opts.docsArtifactRoot = arg.slice("--docs-artifact-root=".length);
    } else if (arg === "--document-name") {
      opts.documentName = argv[++i] || opts.documentName;
    } else if (arg.startsWith("--document-name=")) {
      opts.documentName = arg.slice("--document-name=".length);
    } else if (arg === "--document-schema") {
      opts.documentSchema = argv[++i] || opts.documentSchema;
    } else if (arg.startsWith("--document-schema=")) {
      opts.documentSchema = arg.slice("--document-schema=".length);
    } else if (arg === "--format") {
      opts.format = argv[++i] || opts.format;
    } else if (arg.startsWith("--format=")) {
      opts.format = arg.slice("--format=".length);
    } else {
      throw new Error(`unknown argument: ${arg}`);
    }
  }

  return opts;
}

function run(command, args, cwd) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    maxBuffer: 100 * 1024 * 1024,
  });
  if (result.status !== 0) {
    const detail = (result.stderr || result.stdout || "").trim();
    throw new Error(`${command} ${args.join(" ")} failed (${result.status}): ${detail}`);
  }
  return result.stdout;
}

function parseJson(text, label) {
  try {
    return JSON.parse(text);
  } catch (err) {
    throw new Error(`${label} did not return JSON: ${err.message}`);
  }
}

function firstValue(obj, keys) {
  for (const key of keys) {
    if (obj && obj[key] !== undefined && obj[key] !== null && obj[key] !== "") {
      return obj[key];
    }
  }
  return "";
}

function metadataOf(item) {
  const metadata = item.metadata || item.meta || {};
  return metadata && typeof metadata === "object" ? metadata : {};
}

function isRootTask(item, opts) {
  const status = String(firstValue(item, ["status", "state"])).toLowerCase();
  const type = String(firstValue(item, ["issue_type", "type", "kind"])).toLowerCase();
  const id = String(firstValue(item, ["id", "bead_id", "key", "ID"]));
  const title = String(firstValue(item, ["title", "summary", "name", "description"]));
  const parent = firstValue(item, [
    "parent",
    "parent_id",
    "parentId",
    "root",
    "root_id",
    "rootId",
    "epic",
    "epic_id",
    "epicId",
  ]);
  const metadata = metadataOf(item);
  const gcKind = metadata["gc.kind"] || metadata.gc_kind || "";
  const wispType = metadata["wisp.type"] || metadata.wisp_type || "";

  if (!ACTIVE_STATUSES.has(status)) return false;
  if (type && !ROOT_TYPES.has(type)) return false;
  if (parent) return false;
  if (!opts.includeWorkflowMetadata && gcKind) return false;
  if (!opts.includeWisps) {
    if (/wisp|order/.test(id)) return false;
    if (wispType) return false;
    if (/^order:/.test(title)) return false;
  }
  return true;
}

function inferStage(item) {
  const title = String(firstValue(item, ["title", "summary", "name", "description"]));
  const text = title.toLowerCase();

  if (/requirements?/.test(text)) return "requirements";
  if (/bug|loses|failure/.test(text)) return "bug triage";
  if (/fix|address|remove|apply .*fix|apply .*findings|align|setup clean|workspace|integration gaps|metadata|override/.test(text)) {
    return "implementation/cleanup";
  }
  if (/smoke|verify|verification|test evidence|\btest\b/.test(text)) return "verification";
  if (/finalize|summary|report|describe .*document change|close drain/.test(text)) return "finalization/reporting";
  if (/implementation plan|plan review|produce .*plan|write implementation plan|describe plan|planning/.test(text)) return "planning";
  if (/decompos|create task beads|task decomposition/.test(text)) return "decomposition";
  if (/review|audit|cso|qa evidence|staff engineer|re-review|starter review/.test(text)) return "review";
  if (/publish|pull request|\bpr #/.test(text)) return "publication";
  return "unsorted";
}

function normalizeItem(rig, item) {
  const metadata = metadataOf(item);
  return {
    rig,
    id: String(firstValue(item, ["id", "bead_id", "key", "ID"])),
    status: String(firstValue(item, ["status", "state"])),
    type: String(firstValue(item, ["issue_type", "type", "kind"])),
    priority: firstValue(item, ["priority", "priority_label"]),
    assignee: String(firstValue(item, ["assignee", "owner", "assigned_to"])),
    title: String(firstValue(item, ["title", "summary", "name", "description"])),
    stage: inferStage(item),
    gcKind: metadata["gc.kind"] || metadata.gc_kind || "",
  };
}

function markdownEscape(value) {
  return String(value || "")
    .replace(/\\/g, "\\\\")
    .replace(/\|/g, "\\|")
    .replace(/\r?\n/g, " ");
}

function discoverCityRoot(opts) {
  if (opts.cityRoot) return path.resolve(opts.cityRoot);
  if (process.env.GC_CITY_PATH) return path.resolve(process.env.GC_CITY_PATH);
  const status = parseJson(run("gc", ["status", "--json"], process.cwd()), "gc status --json");
  return path.resolve(status.city_path || status.workspace?.path || process.cwd());
}

function discoverRigs(cityRoot, opts) {
  if (opts.rigs.trim()) {
    return opts.rigs
      .split(",")
      .map((rig) => rig.trim())
      .filter(Boolean);
  }
  const data = parseJson(run("gc", ["rig", "list", "--json"], cityRoot), "gc rig list --json");
  return (data.rigs || [])
    .filter((rig) => !rig.hq)
    .map((rig) => rig.name)
    .filter(Boolean);
}

function fetchRigItems(cityRoot, rig, opts) {
  const args = [
    "--rig",
    rig,
    "bd",
    "list",
    "--status",
    Array.from(ACTIVE_STATUSES).join(","),
    "--json",
    "--limit",
    "0",
    "--include-gates",
  ];
  let raw;
  try {
    raw = run("gc", args, cityRoot);
  } catch (_err) {
    raw = run("gc", args.filter((arg) => arg !== "--include-gates"), cityRoot);
  }
  const data = parseJson(raw, `gc --rig ${rig} bd list`);
  const items = Array.isArray(data) ? data : data.issues || data.items || data.results || [];
  return items.filter((item) => isRootTask(item, opts)).map((item) => normalizeItem(rig, item));
}

function renderMarkdown(rows, cityRoot, opts, generatedAt) {
  const rigs = Array.from(new Set(rows.map((row) => row.rig)));
  const stages = Array.from(new Set(rows.map((row) => row.stage))).sort();
  const byRigStage = new Map();
  for (const row of rows) {
    const key = `${row.rig}\u0000${row.stage}`;
    byRigStage.set(key, (byRigStage.get(key) || 0) + 1);
  }

  const lines = [];
  lines.push("# Root Task Stage Report");
  lines.push("");
  lines.push(`Generated: ${generatedAt}`);
  lines.push(`City root: ${cityRoot}`);
  lines.push("");
  lines.push("## Filters");
  lines.push("");
  lines.push("- Status: open, in_progress, blocked, deferred");
  lines.push("- Types: task, bug, feature, chore");
  lines.push("- Root only: parent/root fields must be empty");
  lines.push(`- Workflow metadata beads: ${opts.includeWorkflowMetadata ? "included" : "excluded when gc.kind is set"}`);
  lines.push(`- Wisps/orders: ${opts.includeWisps ? "included" : "excluded by id/metadata/title"}`);
  lines.push("");
  lines.push("## Summary");
  lines.push("");
  lines.push("| Rig | Total | Stages |");
  lines.push("|---|---:|---|");
  for (const rig of rigs) {
    const rigRows = rows.filter((row) => row.rig === rig);
    const stageText = stages
      .map((stage) => [stage, byRigStage.get(`${rig}\u0000${stage}`) || 0])
      .filter(([, count]) => count > 0)
      .map(([stage, count]) => `${stage}: ${count}`)
      .join(", ");
    lines.push(`| ${markdownEscape(rig)} | ${rigRows.length} | ${markdownEscape(stageText)} |`);
  }
  const allStageText = stages
    .map((stage) => [stage, rows.filter((row) => row.stage === stage).length])
    .filter(([, count]) => count > 0)
    .map(([stage, count]) => `${stage}: ${count}`)
    .join(", ");
  lines.push(`| **All rigs** | **${rows.length}** | ${markdownEscape(allStageText)} |`);

  for (const rig of rigs) {
    lines.push("");
    lines.push(`## ${rig}`);
    lines.push("");
    lines.push("| ID | Status | Type | Stage | Assignee | Title |");
    lines.push("|---|---|---|---|---|---|");
    for (const row of rows.filter((item) => item.rig === rig)) {
      lines.push(
        `| ${markdownEscape(row.id)} | ${markdownEscape(row.status)} | ${markdownEscape(row.type)} | ${markdownEscape(row.stage)} | ${markdownEscape(row.assignee)} | ${markdownEscape(row.title)} |`,
      );
    }
  }

  return `${lines.join("\n").trimEnd()}\n`;
}

function resolvePath(base, value) {
  if (!value) return "";
  return path.isAbsolute(value) ? value : path.resolve(base, value);
}

function resolveOutputPath(cityRoot, opts) {
  const docsRoot = resolvePath(cityRoot, opts.docsArtifactRoot);
  if (opts.output) return resolvePath(docsRoot || cityRoot, opts.output);
  if (docsRoot) return path.join(docsRoot, "root-task-stage-report.md");
  return path.resolve(cityRoot, "reports/root-task-stage-report/root-task-stage-report.md");
}

function resolveManifestPath(cityRoot, opts, outputPath) {
  if (opts.manifest) return resolvePath(cityRoot, opts.manifest);
  const docsRoot = resolvePath(cityRoot, opts.docsArtifactRoot);
  if (docsRoot) return path.join(docsRoot, "manifest.json");
  return path.join(path.dirname(outputPath), "manifest.json");
}

function relativePath(anchor, target) {
  const rel = path.relative(anchor, target);
  return rel && !rel.startsWith("..") ? rel : target;
}

function currentJjChangeId(cwd) {
  try {
    return run("jj", ["log", "-r", "@", "--no-graph", "-T", "change_id.short()"], cwd).trim();
  } catch (_err) {
    return "";
  }
}

function updateManifest(opts, outputPath, manifestPath, content) {
  const manifest = fs.existsSync(manifestPath)
    ? parseJson(fs.readFileSync(manifestPath, "utf8"), manifestPath)
    : {};
  const docsWorkspacePath = resolvePath(process.cwd(), opts.docsWorkspacePath) || process.cwd();
  const docsArtifactRoot = resolvePath(docsWorkspacePath, opts.docsArtifactRoot) || path.dirname(outputPath);
  const hash = crypto.createHash("sha256").update(content).digest("hex");
  const changeId = currentJjChangeId(docsWorkspacePath);

  manifest.schema = manifest.schema || "gc.docs.manifest.v1";
  manifest.workflow = manifest.workflow || "root-task-stage-report";
  manifest.documents = manifest.documents || {};
  manifest.documents[opts.documentName] = {
    path: relativePath(docsWorkspacePath, outputPath),
    schema: opts.documentSchema,
    hash,
    ...(changeId ? { change_id: changeId } : {}),
  };
  manifest.docs = {
    ...(manifest.docs || {}),
    workspace: opts.docsWorkspace,
    workspace_path: docsWorkspacePath,
    artifact_root: docsArtifactRoot,
  };

  fs.mkdirSync(path.dirname(manifestPath), { recursive: true });
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  return { hash, changeId };
}

function main() {
  const opts = parseArgs(process.argv);
  const cityRoot = discoverCityRoot(opts);
  const rigs = discoverRigs(cityRoot, opts);
  const rows = rigs.flatMap((rig) => fetchRigItems(cityRoot, rig, opts));
  const generatedAt = new Date().toISOString();
  const outputPath = resolveOutputPath(cityRoot, opts);
  const manifestPath = resolveManifestPath(cityRoot, opts, outputPath);

  let content;
  if (opts.format === "json") {
    content = `${JSON.stringify({ generatedAt, cityRoot, filters: opts, rows }, null, 2)}\n`;
  } else if (opts.format === "markdown") {
    content = renderMarkdown(rows, cityRoot, opts, generatedAt);
  } else {
    throw new Error(`unsupported format: ${opts.format}`);
  }

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, content);
  const manifestResult = updateManifest(opts, outputPath, manifestPath, content);
  console.log(`root task stage report: ${rows.length} row(s) -> ${outputPath}`);
  console.log(`manifest: ${manifestPath}`);
  console.log(`sha256: ${manifestResult.hash}`);
  if (manifestResult.changeId) console.log(`change_id: ${manifestResult.changeId}`);
}

main();
