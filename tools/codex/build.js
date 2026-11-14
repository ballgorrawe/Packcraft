// Builds the player-facing Codex page from the game files.
// node tools/codex/build.js [out.html]   (default: build/web/codex.html, published with the game)
const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const root = path.resolve(__dirname, "../..");
const out = process.argv[2] || path.join(root, "build/web/codex.html");
const tmp = path.join(require("os").tmpdir(), "packcraft_codex_data.json");
execFileSync(process.execPath, [path.join(__dirname, "export.js"), root, tmp], { stdio: "inherit" });
const tpl = fs.readFileSync(path.join(__dirname, "codex_template.html"), "utf8");
const data = fs.readFileSync(tmp, "utf8").replace(/<\//g, "<\/");
const ver = (fs.readFileSync(path.join(root, "project.godot"), "utf8").match(/config\/version="([^"]+)"/) || [])[1] || "";
// a standalone page needs its own document head; the template is written for the artifact host
const page = "<!doctype html>\n<html lang=\"th\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1, viewport-fit=cover\">\n" +
  tpl.replace("__DATA__", data).replace("(ดึงจากไฟล์เกมเวอร์ชันล่าสุด)", "(เกมเวอร์ชัน " + ver + ")").replace("<div class=\"wrap\">", "</head><body><div class=\"wrap\">") + "\n</body></html>\n";
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, page);
console.log("codex:", out, page.length, "bytes");
