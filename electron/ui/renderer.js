const output = document.querySelector("#output");
const status = document.querySelector("#status");
const buttons = document.querySelectorAll("button");
const capture = document.querySelector("#capture");

window.lab.onOutput((chunk) => {
  output.textContent += chunk;
  output.scrollTop = output.scrollHeight;
});

async function execute(command) {
  output.textContent = "";
  status.textContent = "运行中";
  for (const button of buttons) button.disabled = true;
  try {
    const code = await window.lab.execute(command);
    status.textContent = code === 0 ? "已完成" : "需要处理";
  } catch (error) {
    output.textContent += error.message;
    status.textContent = "需要处理";
  } finally {
    for (const button of buttons) button.disabled = false;
  }
}

document.querySelector("#run").addEventListener("click", () => execute(capture.checked ? "capture" : "ax-only"));
for (const button of document.querySelectorAll("[data-command]")) {
  button.addEventListener("click", () => execute(button.dataset.command));
}
