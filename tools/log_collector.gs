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
// With ?key=<READ_KEY> it returns every log in a compact form (the per-day morning snapshots cut down
// to what the bot tools use), so Claude can download them all at once for bot training.
// READ_KEY lives only in this script's Project Settings > Script properties, never in the game.
function doGet(e) {
  const want = PropertiesService.getScriptProperties().getProperty('READ_KEY');
  const key = e && e.parameter && e.parameter.key;
  if (!want || key !== want) return reply('PackCraft log collector is running.');
  const out = [];
  const files = folder().getFiles();
  while (files.hasNext()) {
    const f = files.next();
    if (!f.getName().endsWith('.json')) continue;
    try {
      out.push(compact(f.getName(), JSON.parse(f.getBlob().getDataAsString())));
    } catch (err) {
      // a junk file: skip it
    }
  }
  return ContentService.createTextOutput(JSON.stringify(out)).setMimeType(ContentService.MimeType.JSON);
}

function compact(name, d) {
  const r = d.run || {};
  const days = (r.days || []).map((day) => {
    const m = day.m || {};
    return {
      d: day.d,
      gold: m.gold, hp: m.hp, mhp: m.mhp, res: m.res, lv: m.lv, path: m.path, mod: m.mod, hz: m.hz,
      tiles: (m.tiles || []).length,
      items: (m.items || []).map((i) => [i.id, i.loc, i.x, i.y, i.rot].join(':')),
      shop: (m.shop || []).map((s) => s.bag ? 'bag' + s.n : s.id + ':' + s.price),
      nodes: (m.nodes || []).map((n) => n.k + (n.e ? ':' + n.e.n : '')),
      a: (day.a || []).map((x) => {
        const c = Object.assign({}, x);
        delete c.shop;   // the reroll's new shop: big, and the next action says what was bought
        return c;
      }),
    };
  });
  return {f: name, ver: d.ver, pid: d.pid, when: d.when, cls: r.cls, pet: r.pet, diff: r.diff, asc: r.asc, path: r.path,
    end: r.end, win: r.win, day: r.day, lv: r.lv, endless: r.endless, hearts: r.hearts, pack: r.pack, days: days};
}

function folder() {
  const it = DriveApp.getFoldersByName(FOLDER_NAME);
  return it.hasNext() ? it.next() : DriveApp.createFolder(FOLDER_NAME);
}

function reply(s) {
  return ContentService.createTextOutput(s);
}
