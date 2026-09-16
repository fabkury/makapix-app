# messages/ — server ↔ app correspondence

Cross-team messages between the Makapix Club **server** team (repo `makapix`)
and this **app** team live here, one sub-folder per thread:

```
messages/
  <NNNN>-<topic>/                 # one thread, e.g. 0001-app-device-type/
    0001-server-<slug>.md         # numbered inside the thread; <from> = server | app
    0002-app-<slug>.md
    …
```

- The server team opens a thread by pushing its `0001-server-…` file here;
  the app team replies in the **same sub-folder** with the next number.
- Thread numbers are global and increasing; file numbers restart at 0001
  inside each thread.
- Each message names the reply it expects (file name) in its header.
- The server keeps its copy under `docs/<effort>/messages/` in its repo.
- For shared matters (API contract, protocol, metrics semantics) the server
  team has the final say; each team decides its own non-shared matters.

Older threads (before 2026-09-09) were delivered as `docs/club-server-cr-*.md`; those files were
retired to git history on 2026-09-16 once their threads had closed.
