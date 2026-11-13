# Firebase setup (leaderboards, later cloud saves)

The game code is ready (`scripts/core/cloud.gd`); it stays off until two values are in `project.godot`.
About 10 minutes, on a computer, signed in to your Google account.

1. Open https://console.firebase.google.com and click **Create a project**. Name it `packcraft`.
   Google Analytics: off. Wait until it says the project is ready.
2. **Build > Authentication > Get started > Sign-in method > Anonymous > Enable > Save.**
3. **Build > Firestore Database > Create database.** Location: `asia-southeast1` (Singapore).
   Start in **production mode**.
4. Firestore **Rules** tab: replace everything with the rules below and click **Publish**.
5. **Project settings** (gear) **> General > Your apps > Web (`</>`)**. Nickname `packcraft-web`,
   no Hosting. Copy `apiKey` and `projectId` from the config it shows and send them to Claude.
   (The web API key is not a secret: the rules below decide who may write what.)

Claude then puts them in `project.godot` as `packcraft/firebase_api_key` and `packcraft/firebase_project`.

## Firestore rules

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // boards/{board}/scores/{uid}: everyone can read; each player writes only their own row
    match /boards/{board}/scores/{uid} {
      allow read: if true;
      allow write: if request.auth != null && request.auth.uid == uid
        && request.resource.data.keys().hasOnly(['score', 'name', 'cls', 'ver'])
        && request.resource.data.score is int
        && request.resource.data.score >= 0 && request.resource.data.score < 100000
        && request.resource.data.name is string && request.resource.data.name.size() <= 20;
    }
  }
}
```

Scores are sent by the game, so a determined player can fake one; the rules only cap the obvious.
Weekly boards (a new board each week) keep any fake score short-lived.
