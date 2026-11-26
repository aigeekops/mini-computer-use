const { app, BrowserWindow, ipcMain, net, protocol } = require("electron");
const { spawn } = require("node:child_process");
const path = require("node:path");
const { pathToFileURL } = require("node:url");

const root = path.join(__dirname, "..");
const helper = path.join(root, ".build", "mini-computer-use");
const home = "mini-use://lab/index.html";
const assets = new Set(["/index.html", "/style.css", "/renderer.js"]);
const commands = new Map([
  ["status", ["status"]],
  ["accessibility", ["request-accessibility"]],
  ["screen", ["request-screen"]],
  ["ax-only", ["run", "--ax-only"]],
  ["capture", ["run"]],
]);
let window;
let activeChild;

protocol.registerSchemesAsPrivileged([
  { scheme: "mini-use", privileges: { standard: true, secure: true, supportFetchAPI: true } },
]);

ipcMain.handle("lab:execute", (event, action) => {
  if (event.sender !== window?.webContents || event.senderFrame !== event.sender.mainFrame
      || event.senderFrame?.url !== home) {
    throw new Error("This request did not come from the demo window.");
  }
  const args = commands.get(action);
  if (!args) throw new Error("Unknown demo command.");
  if (activeChild) throw new Error("A command is already running.");

  return new Promise((resolve) => {
    const child = spawn(helper, args, { cwd: root, stdio: ["ignore", "pipe", "pipe"] });
    activeChild = child;
    const log = (chunk) => {
      if (!event.sender.isDestroyed()) event.sender.send("lab:output", chunk);
    };
    for (const stream of [child.stdout, child.stderr]) {
      stream.setEncoding("utf8");
      stream.on("data", log);
    }
    child.once("error", (error) => log(
      error.code === "ENOENT" ? "Run npm run build:native first.\n" : `${error.message}\n`,
    ));
    child.once("close", (code) => {
      activeChild = undefined;
      resolve(code ?? 1);
    });
  });
});

async function openWindow() {
  protocol.handle("mini-use", (request) => {
    const url = new URL(request.url);
    if (url.host !== "lab" || !assets.has(url.pathname)) return new Response(null, { status: 404 });
    return net.fetch(pathToFileURL(path.join(__dirname, "ui", url.pathname.slice(1))).href);
  });
  const smokeTest = process.argv.includes("--smoke-test");
  window = new BrowserWindow({
    width: 970,
    height: 620,
    minWidth: 590,
    minHeight: 460,
    backgroundColor: "#edf2f5",
    show: !smokeTest,
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      sandbox: true,
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  window.webContents.on("will-navigate", (event) => event.preventDefault());
  window.on("close", (event) => {
    if (!activeChild) return;
    event.preventDefault();
    window.hide();
    activeChild.once("close", () => window.close());
  });
  await window.loadURL(home);

  if (smokeTest) {
    const passed = await window.webContents.executeJavaScript(`(async () => {
      if (!document.querySelector("#run") || typeof require !== "undefined") return false;
      const button = document.querySelector('[data-command="status"]');
      button.click();
      for (let attempt = 0; attempt < 100 && button.disabled; attempt++) {
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
      const log = document.querySelector("#output").textContent;
      if (button.disabled || !log.includes("Accessibility:") || !log.includes("Screen recording:")) return false;
      try { await window.lab.execute("invalid"); } catch { return true; }
      return false;
    })()`);
    if (passed && process.env.DEMO_SCREENSHOT) {
      const screenshot = await window.webContents.capturePage();
      await require("node:fs/promises").writeFile(process.env.DEMO_SCREENSHOT, screenshot.toPNG());
    }
    console.log(passed ? "Electron IPC smoke test passed." : "Electron IPC smoke test failed.");
    app.exit(passed ? 0 : 1);
  }
}

app.whenReady().then(openWindow).catch((error) => {
  console.error(error);
  app.exit(1);
});
app.on("window-all-closed", () => app.quit());
