# Offline Tasks – offline-first task manager (Flutter)

A to-do app that works fully without internet and syncs to a server when the connection returns, without losing data or creating duplicates.

Two parts:

| Part | Folder | What it is |
|---|---|---|
| Mobile app | `app/` | Flutter app, stores everything in SQLite on the phone |
| Server | `server/` | ~100-line Node.js server acting as the "remote database" (no accounts or cloud setup needed) |

## Features

- Create, edit, delete tasks; complete/pending; priority (low/medium/high); deadline (date + time); category tag
- Search, filter by status and category; overdue tasks highlighted
- Swipe to delete with **Undo**
- Works offline: all data in SQLite, survives closing/restarting the app
- Online/offline banner, plus how many changes are waiting to sync
- **Simulate offline** switch (menu) for demos and testing
- Sync activity log (menu → *Sync activity log*): pushes, pulls, retries, conflicts
- Loading, empty ("no tasks yet" / "no tasks match") and error states

## Run it

### 1. Start the server (needs Node.js)

```bash
cd offline_tasks/server
node server.js
```

Leave it running. It prints `Task server listening on http://0.0.0.0:3000`.

### 2. Set up Flutter (once)

Install Flutter from <https://docs.flutter.dev/get-started/install>, then `flutter doctor` and fix what it reports (you need the Android SDK and either an emulator or a phone with USB debugging).

### 3. Run the app

```bash
cd offline_tasks/app
flutter pub get
flutter run
```

The Android project (including internet permission and `http://` access for the demo server) is already included. If you ever regenerate it with `flutter create`, run `python tools/patch_android_manifest.py` afterwards.

### Which server address?

- **Android emulator:** nothing to do (`http://10.0.2.2:3000` is the default; that is the emulator's name for your computer).
- **Real phone:** phone and computer on the same Wi-Fi. In the app: menu → *Server address* → `http://<your computer's IP>:3000` (find the IP with `ipconfig`). Allow Node.js through the Windows firewall when asked.

### Build the APK

```bash
cd offline_tasks/app
flutter build apk --release
```

Output: `app/build/app/outputs/flutter-apk/app-release.apk`.

## Test it (also the demo-video script)

1. Start the server, open the app. Banner says **Online – all changes synced**.
2. Menu → **Simulate offline** (or turn on airplane mode). Banner turns to **Offline**.
3. Add 2 tasks, edit one, complete one, delete one. Everything updates instantly; banner shows e.g. "4 waiting to sync".
4. Fully close and reopen the app: tasks and the waiting count are still there.
5. Turn offline off. The app syncs by itself; banner returns to **all changes synced**. Check *Sync activity log*.
6. **No duplicates:** tap *Sync now* repeatedly, or kill the app mid-sync and reopen. Task count stays the same.
7. **Retry:** stop the server (Ctrl+C), edit a task: banner says *Can't reach server – will retry*. Restart the server; the change goes through on its own.
8. **Conflict:** with the server running, make an edit on the phone while offline. Meanwhile change the same task on the server:
   ```bash
   curl -X PUT http://localhost:3000/tasks/<id> -H "content-type: application/json" \
     -d '{"title":"Changed on server","baseVersion":<current version>,"opId":"manual-1"}'
   ```
   (`GET http://localhost:3000/tasks` shows ids and versions.) Go back online: the activity log shows the merge.
9. `POST http://localhost:3000/reset` wipes the server for a fresh demo.

## How it works

### Offline storage
SQLite (`sqflite`) holds four tables: `tasks`, `outbox` (changes waiting to sync), `sync_log`, `meta`. The UI reads from the in-memory list, which is updated immediately on each action and then written to SQLite. A task edit and its outbox entry are written in **one transaction**, so a change can never be saved without also being queued.

### Synchronisation
1. **Push:** for each outbox entry, `PUT /tasks/:id` with the task, the server version it was based on (`baseVersion`) and a unique `opId`. The entry is deleted only **after** the server confirms.
2. **Pull:** `GET /tasks?since=<seq>` returns everything changed since the last sync; stored in SQLite and applied.
3. **Triggers:** shortly after every edit, when connectivity returns, every 15 s, on app start, and via *Sync now* / pull-to-refresh.
4. **Retry:** failures back off exponentially (4 s, 8 s, 16 s … max 5 min), with the error kept in the outbox and shown in the log.
5. **No duplicates:** ids are UUIDs created on the phone and the server upserts by id; `opId` makes a resend after a lost reply a no-op (tested in `server/test_server.js`).
6. **Restart safety:** the queue and `last_seq` are in SQLite, so killing the app mid-sync only means the entry is sent again, which is harmless. On start the app syncs immediately.
7. **Edit during sync:** if you edit a task while its previous version is being uploaded, the new edit stays queued instead of being marked synced.

### Conflict resolution
The server rejects a push whose `baseVersion` is not its current version (HTTP 409 and its copy). The app then runs a **three-way merge** of *base* (last version both sides agreed on), *local* and *remote*, per field:

- changed only on one side → that change is kept (so changing the title here and the priority elsewhere keeps both, silently)
- **same field changed on both sides to different values → the task is flagged "Needs your review"** and held back from syncing; the user picks *Keep both* (merge, newest edit wins for the clashing field), *Keep mine* or *Keep the other device*
- **delete vs edit → the edit wins**, so nobody silently loses work
- reordering (drag-and-drop) never raises a conflict; the newest order wins

Resolved results are pushed immediately and every conflict is written to the activity log. Code: `app/lib/sync/conflict.dart`, tests in `app/test/conflict_test.dart`.

## Project layout

```
app/lib/models/task.dart       Task model
app/lib/data/local_db.dart     SQLite: tasks, outbox, log
app/lib/sync/remote_api.dart   HTTP client for the server
app/lib/sync/sync_engine.dart  push / pull / retry loop
app/lib/sync/conflict.dart     three-way merge (pure, unit-tested)
app/lib/state/task_store.dart  app state, filters, optimistic edits
app/lib/ui/                    screens
server/server.js           the remote database
```

Tests: `flutter test` inside `app/` (merge logic) and `node server/test_server.js` (server).

## Bonus features

Activity log, deadline notifications, recurring tasks (daily/weekly/monthly), drag-and-drop reordering, and multi-device use (two phones pointed at the same server share one task list; there are no user accounts).
