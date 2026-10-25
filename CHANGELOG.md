## 0.2.0

- Upgrade to `dbmigrator` ^0.2.0.
- Note: `dbmigrator` 0.2.0 changed how checksums are computed. Existing version tables created with 0.1.x may need to follow the migration options described in the `dbmigrator` 0.2.0 changelog.
- `migrate()` now rejects target versions that have no `up`/`down` files (`MigrationInvalidVersionError`), e.g. downgrading to a non-existent `0.0.0`.
- Tests: downgrade tests now target an existing no-op `0.0.1` migration.

## 0.1.3

- Initial version.
