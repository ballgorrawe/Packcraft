// PackCraft play-log collector (Google Apps Script web app).
// Every finished or abandoned run in the web game is POSTed here and saved as one JSON file in a
// Drive folder named "PackCraft logs". The logs are read later to train and check the balance bot.
//
// Setup (once, on a computer):
//   1. Open https://script.google.com and click "New project".
//   2. Delete the sample code, paste this whole file, and save (name it "PackCraft logs").
//   3. Click Deploy > New deployment > the gear icon > "Web app".
//        Execute as: Me
//        Who has access: Anyone
//      Click Deploy, allow the Drive permission it asks for, and copy the "Web app URL"
//      (https://script.google.com/macros/s/.../exec).
//   4. Send that URL to Claude: it goes into project.godot as packcraft/log_url.
//
// The URL ships inside the game, so anyone could post to it. The script only accepts PackCraft
// payloads (key + run data) up to 1 MB, so the worst case is junk files in that one folder.

const FOLDER_NAME = 'PackCraft logs';
const KEY = 'pc1';
const MAX_BYTES = 1000000;

function doPost(e) {
  try {
    const body = (e && e.postData && e.postData.contents) || '';
    if (body.length > MAX_BYTES) return reply('too big');
    const d = JSON.parse(body);
    if (d.k !== KEY || !d.run || !Array.isArray(d.run.days)) return reply('rejected');
    const r = d.run;
    const safe = (s) => String(s || '').replace(/[^A-Za-z0-9_.-]/g, '').slice(0, 24);
    const name = [
      new Date().toISOString().replace(/[:.]/g, '-'),
      safe(r.diff), safe(r.cls), safe(r.end), 'd' + Number(r.day || 0), safe(d.pid),
    ].join('_') + '.json';
    folder().createFile(name, body, 'application/json');
    return reply('ok');
  } catch (err) {
    return reply('error');
  }
}

// Opening the URL in a browser just says it is running.
function doGet() {
  return reply('PackCraft log collector is running.');
}

function folder() {
  const it = DriveApp.getFoldersByName(FOLDER_NAME);
  return it.hasNext() ? it.next() : DriveApp.createFolder(FOLDER_NAME);
}

function reply(s) {
  return ContentService.createTextOutput(s);
}
