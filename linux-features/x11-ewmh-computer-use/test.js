"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { execFileSync } = require("node:child_process");

const featureDir = __dirname;
const featureId = "x11-ewmh-computer-use";

function upstreamRepoRoot() {
  const candidates = [
    process.env.CODEX_DESKTOP_LINUX_REPO,
    process.env.CODEX_DESKTOP_LINUX_FULL_PATH,
    path.resolve(featureDir, "..", ".."),
    "/home/as/Документы/AI_PROJECTS/codex-desktop-linux",
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, "scripts/lib/linux-features.js"))) {
      return candidate;
    }
  }
  throw new Error("Could not locate codex-desktop-linux scripts/lib/linux-features.js; set CODEX_DESKTOP_LINUX_REPO");
}

function linuxFeaturesLib() {
  const repoRoot = upstreamRepoRoot();
  return require(path.join(repoRoot, "scripts/lib/linux-features.js"));
}

function copyFeatureTo(featuresRoot) {
  const target = path.join(featuresRoot, featureId);
  fs.mkdirSync(target, { recursive: true });
  for (const file of ["feature.json", "README.md", "stage.sh", "patches.js"]) {
    fs.copyFileSync(path.join(featureDir, file), path.join(target, file));
  }
  fs.chmodSync(path.join(target, "stage.sh"), 0o755);
}

function tempDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), `${prefix}-`));
}

function makeFakeExecutable(file) {
  fs.writeFileSync(file, "#!/bin/sh\nif [ \"$1\" = doctor ]; then echo '{\"project\":\"codex-computer-use-x11\",\"version\":\"test\",\"backend\":\"x11-ewmh\",\"readiness\":{\"ok\":true}}'; fi\nexit 0\n");
  fs.chmodSync(file, 0o755);
}

function applyPatchTwice(patchFn, source) {
  const patched = patchFn(source);
  assert.equal(patchFn(patched), patched);
  return patched;
}


test("x11-ewmh-computer-use documents and pins v0.1.3 release artifact", () => {
  const stage = fs.readFileSync(path.join(featureDir, "stage.sh"), "utf8");
  const readme = fs.readFileSync(path.join(featureDir, "README.md"), "utf8");
  const url = "https://github.com/AlekseiSeleznev/codex-computer-use-x11/releases/download/v0.1.3/codex-computer-use-x11-v0.1.3-x86_64-unknown-linux-gnu.tar.gz";
  const sha = "067244a16f9e812eb369af42149658c8cf138b13057445bb9d10318f29b0c26b";
  assert.equal(stage.includes(url), true);
  assert.equal(stage.includes(sha), true);
  assert.equal(readme.includes(url), true);
  assert.equal(readme.includes(sha), true);
});

test("x11-ewmh-computer-use stays disabled until listed in features.json", () => {
  const { enabledLinuxFeatureStageHooks, loadLinuxFeaturePatchDescriptors } = linuxFeaturesLib();
  const workspace = tempDir("x11-ewmh-feature");
  const featuresRoot = path.join(workspace, "features");
  fs.mkdirSync(featuresRoot, { recursive: true });
  copyFeatureTo(featuresRoot);
  fs.writeFileSync(path.join(featuresRoot, "features.example.json"), '{"enabled":[]}\n');

  assert.deepEqual(enabledLinuxFeatureStageHooks({ featuresRoot }), []);
  assert.deepEqual(loadLinuxFeaturePatchDescriptors({ featuresRoot }), []);

  fs.writeFileSync(path.join(featuresRoot, "features.json"), `{"enabled":["${featureId}"]}\n`);
  assert.equal(enabledLinuxFeatureStageHooks({ featuresRoot }).length, 1);
  assert.equal(loadLinuxFeaturePatchDescriptors({ featuresRoot }).length, 1);
});

test("x11-ewmh-computer-use plugin gate is idempotent and narrow", () => {
  const { applyX11ComputerUsePluginGatePatch } = require("./patches.js");
  const source = [
    "var lt=`browser-use`,ft=`computer-use`,pt=`latex-tectonic`;",
    "var Kr=[{forceReload:!0,installWhenMissing:!0,name:lt,isAvailable:({features:e})=>e.inAppBrowserUseAllowed},{name:ft,isAvailable:({features:e,platform:t})=>t===`darwin`&&e.computerUse,migrate:vr},{name:pt,isAvailable:()=>!0}];",
  ].join("");
  const patched = applyPatchTwice(applyX11ComputerUsePluginGatePatch, source);
  assert.match(patched, /name:`codex-computer-use-x11`,isAvailable:\(\{platform:e\}\)=>e===`linux`/);
  assert.match(patched, /name:ft,isAvailable:\(\{features:e,platform:t\}\)=>t===`darwin`&&e\.computerUse/);
});

test("x11-ewmh-computer-use stage hook records marketplace entry and preserves computer-use", () => {
  const workspace = tempDir("x11-ewmh-stage");
  const installDir = path.join(workspace, "install");
  const workDir = path.join(workspace, "work");
  const fakeBinary = path.join(workspace, "codex-computer-use-x11");
  const computerUseDir = path.join(installDir, "resources/plugins/openai-bundled/plugins/computer-use");
  const computerUseMarker = path.join(computerUseDir, ".mcp.json");
  const marketplace = path.join(installDir, "resources/plugins/openai-bundled/.agents/plugins/marketplace.json");
  fs.mkdirSync(computerUseDir, { recursive: true });
  fs.mkdirSync(path.dirname(marketplace), { recursive: true });
  fs.writeFileSync(computerUseMarker, '{"mcpServers":{"computer-use":{"command":"./bin/codex-computer-use-linux"}}}\n');
  fs.writeFileSync(marketplace, JSON.stringify({ plugins: [{ name: "computer-use", source: { path: "./plugins/computer-use" } }] }));
  const beforeComputerUse = fs.readFileSync(computerUseMarker, "utf8");
  makeFakeExecutable(fakeBinary);

  execFileSync("bash", [path.join(featureDir, "stage.sh")], {
    cwd: workspace,
    env: {
      ...process.env,
      SCRIPT_DIR: upstreamRepoRoot(),
      INSTALL_DIR: installDir,
      WORK_DIR: workDir,
      ARCH: process.arch === "arm64" ? "aarch64" : "x86_64",
      CODEX_UPSTREAM_APP_DIR: path.join(workspace, "Codex.app"),
      CODEX_X11_COMPUTER_USE_BINARY: fakeBinary,
    },
    stdio: "pipe",
  });

  const pluginDir = path.join(installDir, "resources/plugins/openai-bundled/plugins/codex-computer-use-x11");
  assert.equal(fs.existsSync(path.join(pluginDir, ".mcp.json")), true);
  assert.equal(fs.existsSync(path.join(pluginDir, "bin/codex-computer-use-x11")), true);
  assert.equal(fs.statSync(path.join(pluginDir, "bin/codex-computer-use-x11")).mode & 0o111 ? true : false, true);
  assert.equal(fs.readFileSync(computerUseMarker, "utf8"), beforeComputerUse);

  const parsedMarketplace = JSON.parse(fs.readFileSync(marketplace, "utf8"));
  assert.equal(parsedMarketplace.plugins.some((plugin) => plugin.name === "codex-computer-use-x11" && plugin.source?.path === "./plugins/codex-computer-use-x11" && plugin.policy?.authentication === "ON_INSTALL"), true);
  assert.equal(parsedMarketplace.plugins.some((plugin) => plugin.name === "computer-use"), true);
});
