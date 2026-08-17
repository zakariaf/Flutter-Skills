# Restore: the validation ladder, the swap, and merge policy

## The validation ladder — cheapest and most destructive-to-skip first

Each rung returns a distinct typed failure, and nothing below a rung runs until it
passes. The order matters: every rung that runs later than it should is a chance to
touch the user's data before knowing the file is real.

1. **Readable** — the picked file opens and is non-empty. (`RestoreFailure.unreadable`)
2. **Ours** — the format marker and `formatVersion` parse from the header.
   (`notOurFormat`, `unsupportedFormatVersion`)
3. **Intact** — the payload checksum matches. Verify **before** parsing the payload; a
   truncated file otherwise fails somewhere random and reports the wrong reason.
   (`corrupt`)
4. **Not from the future** — `schemaVersion <= kSchemaVersion`. Refuse a newer file
   outright with a message naming the app version that wrote it; never "best effort"
   parse it. (`newerThanApp`)
5. **Well-formed** — every row parses into a value object; required fields present;
   enum codes known; instants parse as UTC. (`malformed`, with the first offending
   record identified)
6. **Consistent** — referential integrity holds *within the file* (every referenced id
   exists), and ids are unique. (`inconsistent`)
7. **Applicable** — enough free disk for the staging copy. (`noSpace`)

Only now does anything get written.

## Staging and the swap

```
1. Create staging.db in the app's own directory (never over the live file).
2. Import the whole payload inside ONE transaction. Any failure → close, delete
   staging files, return the typed failure. The live database was never opened for
   write, so the user's data is byte-unchanged.
3. Migrate the staged database forward through the SAME step-by-step path as the app
   database (`run-migration`) when schemaVersion < current. Never a bespoke
   "import-time upgrade" — two migration paths diverge within one release.
4. Close EVERY handle to both databases, including any watched-stream connections.
5. Rename the live file to live.db.prev, then rename staging.db to live.db, then open
   it. If the open fails, rename live.db.prev back and report — this is the rollback.
6. Delete live.db.prev only after the new database opens cleanly and passes
   `PRAGMA integrity_check`.
```

WAL sidecars travel with the file: a `-wal`/`-shm` left from the previous database next
to a renamed-in file is a corruption source. Checkpoint and delete them as part of the
swap, exactly as in the backup primitive (`persistence-drift`).

Restarting the app after a successful swap is the honest, cheap option: every provider,
DAO, and watched stream in memory refers to a database that no longer exists.

## Merge policies

| Policy | What it does | Right when | The cost the user must be told |
|---|---|---|---|
| **Replace** | Wipe local state, import the file as the whole truth | Restoring onto a new/reset device | Everything created since the backup is gone |
| **Merge by id** | Upsert per stable id; conflicts resolved by `updatedAtUtc` (last write wins) | Two devices, or a partial re-import | A locally edited record can be overwritten by an older-looking newer file |
| **Add as copies** | Import everything under fresh ids | Importing someone else's data set | Duplicates by design; the user must dedupe manually |

Pick one per feature and name it in the confirmation, in the same words as the code.
"Restore" alone means whatever the user is afraid it means.

**Merge-by-id needs a real `updatedAtUtc` on every row**, written on every mutation
through the single write path (`state-management-riverpod`), from the injected `Clock`.
Without it, last-write-wins is a guess. Note honestly that wall-clock ordering across
devices with skewed clocks is approximate — if the domain cannot tolerate that, the
policy must be replace or add-as-copies, not merge.

## Reporting the outcome

Return a `RestoreReport`, not a bool: rows imported per entity, rows skipped and why,
the file's `appVersion`/`exportedAtUtc`, and the policy applied. The user's next
question after "Restored" is always "restored *what*", and a support conversation
without those numbers is unresolvable.

**Partial success is not a thing.** Either the transaction and swap completed, or
nothing changed. A report listing "412 of 500 imported" means the ladder let malformed
records through and the file should have been refused at rung 5.
