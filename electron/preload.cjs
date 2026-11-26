const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("lab", {
  execute: (action) => ipcRenderer.invoke("lab:execute", action),
  onOutput: (callback) => {
    ipcRenderer.on("lab:output", (_event, chunk) => callback(chunk));
  },
});
