# Spendy

Spendy (repository/package name: Expencify) is a Flutter expense tracker with local SQLite storage and BLoC state management.

## Features

- Manual transactions, account balances, split expenses and category reports.
- Budgets, goals, bill reminders, subscriptions and appliance AMC reminders.
- Optional Android bank-SMS capture, receipt OCR and voice entry.
- Optional on-device Qwen3 0.6B inference on compatible 64-bit Android devices; iOS retains its existing Qwen2.5 runtime.
- Encrypted local backups and optional Google Drive backup/restore.

SMS access, a battery exemption and an AI model are optional. Manual tracking can be used after accepting the terms.

## Data protection and backups

The live financial database uses SQLCipher with a random 256-bit device-local key held in platform secure storage. The key is separate from the app PIN, so PIN changes do not prevent background SMS processing or database access. Android automatic system backup is disabled.

On upgrade, the app exports the existing plaintext database into an encrypted staging file, compares table contents, preserves the schema version and verifies database integrity before switching files and removing the old database and its journal files. Interrupted migrations can be retried. A missing or invalid key stops startup with a recovery message; it never silently creates a replacement for an existing encrypted database. Keep a passphrase-protected backup: clearing app storage or losing the device key can make the local database unrecoverable.

Database tables and WAL pages are encrypted. Receipt image files and the native pending-SMS queue are separate from the database and are not encrypted by SQLCipher. App Lock controls access through the UI. Deleting the old plaintext files does not guarantee forensic erasure of historical flash-storage blocks.

App PINs use platform secure storage, with migration from older SharedPreferences entries. Repeated incorrect PIN attempts trigger a cooldown. Biometrics use the device authentication API.

New local and Drive backups use AES-256-GCM with a fresh random salt and nonce and PBKDF2-HMAC-SHA256 (600,000 iterations). A separate passphrase of at least 12 characters is required. Keep it safely: it cannot be recovered from the app PIN. Encryption work runs outside the UI isolate.

Backups contain a consistent snapshot of financial tables and available receipt images. Restore validates the format, rows, account references and split totals, then commits through one SQLite transaction. Invalid backups leave the current financial data intact. App-lock credentials, Google sign-in credentials and legal acceptance remain device-local. Legacy SQLite backups from schema versions 1–16 (including files shared as `.bin`) are recognized by their contents and upgraded in an isolated temporary copy before transactional restore. Account opening-balance metadata is preserved separately from the saved current balance. Plain database backups do not ask for a passphrase. Legacy CBC encrypted backups can also be imported using the PIN used at creation. File selection cancellation is separate from invalid-file, unlock and restore errors. Missing receipt files in old database-only backups cannot be recovered.

No external financial inference API is configured. Google Drive uploads are an explicit optional action; model downloads and update checks also require internet access. Voice recognition behavior depends on the device's speech service.

## Platform scope

Android is the primary integration target for SMS and background monitoring. iOS supports a subset of the integrations and does not expose an SMS inbox to this app. Desktop/web folders are scaffolding, not a promise of feature parity. The current AI runtime is guarded to Android/iOS; unsupported platforms do not offer a broken desktop model download.

Recurring reminders use calendar arithmetic and schedule the next 24 occurrences, replenished when the app starts or the item is loaded/changed. End-of-month and leap-day anchors are retained. Android alarms use inexact scheduling, so delivery time can vary with OS restrictions. Notification taps open the related screen after onboarding and unlocking. This feature still needs physical-device validation, including platform limits on scheduled notifications.

## Development

Validated toolchain: Flutter 3.47.7 / Dart 3.13.5. Use the committed lockfile.

```sh
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter test --no-pub plugins/telephony/test
flutter build apk --debug --no-pub
```

The repository includes regression tests for transaction/balance rollback, split invariants, SMS idempotency, migration, resets, backup restoration, model downloads, recurrence, PIN migration and account-scoped budget alerts. CI runs analyzer and both test suites on Windows.

`integration_test/database_encryption_test.dart` exercises real SQLCipher on Android: migration of committed WAL rows, encrypted database/WAL bytes, incorrect or missing keys, secure-storage persistence and concurrent background isolates. Run it with `flutter test integration_test/database_encryption_test.dart -d <device-id>` on a disposable emulator or a source copy with a separate application ID; integration tests install an app. The desktop migration tests use a fake cipher driver and do not establish native encryption correctness.

For Android release builds, supply your own `android/key.properties` and release keystore. Release packaging fails without them instead of using a debug certificate. Configure OAuth for your package/signing certificate to use Google Drive; no credentials are supplied by this repository. The Google Services Gradle plugin is applied only when `android/app/google-services.json` is present.

The AI runtime is pinned to `flutter_gemma` 0.11.16. The publisher has discontinued it in favor of `flutter_edge_ai`; replacing the native inference runtime requires a separate device compatibility validation. The current implementation pins a valid model revision, exact byte count and SHA-256 checksum so downloads cannot silently accept a partial or corrupt file.

## Architecture

```text
lib/domain/          Entities and repository contracts
lib/infrastructure/  SQLite schema, migrations and atomic repositories
lib/application/     BLoCs, backup, SMS, AI and notification services
lib/presentation/    Screens and theme
plugins/telephony/   Locally maintained SMS plugin
```

See [PROJECT_REVIEW.md](PROJECT_REVIEW.md) for the original findings and the remediation record.

## License

This project is personal and private property.

Recurring reminders can be marked as handled to advance to their next future due date while retaining their original calendar anchor. Handling a one-time reminder removes it from active reminders. Neither action records a payment or expense.

Tracking mode: first setup offers manual entry or bank SMS tracking. SMS tracking requires an explicit enable action, SMS permission and configured bank details. Settings > Transaction tracking > Track bank SMS can enable or disable it later. Manual mode blocks native receiver collection and Dart processing while preserving saved transactions. Re-enabling scans only the newly enabled period. Existing installs retain previously granted SMS tracking on first launch after upgrade unless explicitly switched off. Notification permission is requested when enabling SMS or saving notification-based features rather than on app startup.

First setup requires accepted privacy terms. On-device AI is optional and is prepared when a user chooses voice entry, chat, or AI receipt suggestions. Android uses the approximately 343 MB LiteRT Community Qwen3 0.6B INT4 model with LiteRT-LM 0.19.0. Its .litertlm artifact is pinned to an exact revision, file size and checksum. The runtime owns the conversation template, runs off the UI thread, disables thinking, and supports GPU execution with CPU fallback. Setup checks device compatibility before offering a download and supports verified local import. iOS retains the existing 547 MB Qwen2.5-0.5B MediaPipe model until its new native adapter is available. Runtime caches require additional storage; download size is not RAM usage. Manual entry and basic receipt text recognition work without it; scanned details are reviewed before saving. Tracking mode remains a separate manual/SMS choice, and manual mode does not request SMS permission. Returning launches do not load the model until an AI feature needs it.

### Saved merchants, SMS review and local semantic search

The merchant field > Manage saved merchants uses “When an SMS contains → Show merchant as → Use category”, with a live preview. Matching is case-insensitive and whitespace-insensitive, and applies to future messages, not past records. Overlapping duplicate keywords are rejected by the editor. The longest matching keyword takes priority. When correcting an SMS transaction, “Remember for future SMS” opens the same editor; existing named merchants are reused when unambiguous.

Uncertain completed-payment alerts are retained in SMS to review inside SQLCipher. Transactions exposes the pending count and Settings also links to the inbox. Review requires amount, category and account, and an explicit direction when parsing cannot establish one. Saving commits the transaction, processed identity and inbox removal atomically; ignoring also records the identity to resist replay. OTPs, promotions, pending and failed-payment alerts are not collected for review. Sender and bank aliases help distinguish equal account suffixes but do not authenticate a sender.

Improved search is optional in Transactions > Search options > Improve search. One search field always handles keyword matches and automatically includes semantic matches once enabled; there is no separate search-mode selector. Saved merchants and semantic search have contextual controls rather than separate Settings shortcuts. A pinned, SHA-256-verified 23,026,053-byte MiniLM int8 model is downloaded after opt-in; the ONNX runtime is part of the app and increases its binary size separately. English is the initial supported search language. Old and new transactions are indexed in small resumable batches on the active app, with a 40 ms yield between records. Indexing pauses when the app leaves the foreground. Model sessions are released on backgrounding. Vectors use merchant/category/notes, not numerical amounts or account identifiers, and remain in the encrypted live database. Edit/delete triggers invalidate vectors. Backup restore/reset clears derived vectors; rebuilding uses the original records. Disabling search clears vectors while retaining the downloaded model for reuse.

Retrieval combines exact cosine search and local BM25 with reciprocal rank fusion, respecting the chosen account, date, type and category filters. Semantic results are capped at 50 matching records. Keyword-only search remains the default, works during indexing, and is the fallback on inference failures. Chat can include six retrieved source records, explicitly labelled partial evidence. Financial totals remain repository/SQL calculations; semantic matches must never be presented as a complete total. No additional cross-encoder model is shipped in this iteration.

The native embedding plugin requires iOS 16; the project minimum was updated accordingly. Android remains the tested integration platform. License and attribution are bundled under assets/search and available in Settings > Privacy Policy > Open-source licenses. The search setup itself uses one enable action and short progress/status text.

### Chat UX and model guardrails

Chat now uses a compact start screen, selectable/copyable answers, animated waiting feedback, disabled empty/busy sends and failed-reply retry. The latest 120 messages persist in SQLCipher and can be cleared from the conversation menu; chat is excluded from backups. Clear/reset/restore invalidate pending replies so erased messages cannot be reintroduced. On-device privacy details describe this retention.

Model suggestions now require complete valid JSON, source-grounded amounts/splits and supported dates. Truncated JSON repair and higher-randomness retry were removed. Ambiguous edit/delete targets require selecting the transaction instead of taking the first match. Chat has bounded input/context/output, quoted data boundaries and an output check for unsupported numbers, external URLs and common banking-secret requests. These checks do not prove factual accuracy or injection immunity.

MiniLM adds bounded text processing, invalid-vector rejection and serialized timeout quarantine with keyword fallback. Runtime work is not forcibly terminated on timeout. See docs/model-guardrails.md for exact protections and limitations. Model/runtime versions are unchanged.

### Read-only chat scope

Chat supports recorded spending/income/balance/budget questions and fixed app help. It does not provide financial or investment advice. Known advice, unsafe and off-topic requests are answered by fixed policy replies before model generation. Generated responses are screened for advisory or unsafe content as well. Conservative English request patterns can reject valid rephrasings; this boundary does not replace adversarial evaluation or guarantee every possible malicious output is detected. Voice advice requests are also refused before intent generation. Model versions are unchanged.

### Insights accuracy and presentation

Insights now shows selected account and actual date ranges, with descriptive spending comparisons against the equivalent prior period. Month/year-to-date comparisons clamp calendar boundaries; custom ranges compare an equal number of calendar days. All-time totals do not imply a monthly period. No model or financial recommendations are used.

Category charts retain small values and group remaining categories without rescaling away their amounts. Category details preserve filters, count split leaves once, and list all matching transactions. Loading/error/retry states and request generation checks prevent stale results overwriting newer selections. Layout tests cover normal and doubled text sizes.

Validation: 228 Flutter tests passed, including eight new Insights date/math/UI/error/race tests. Widget previews were visually checked; no release APK was built for this update.

### Transaction refresh stability and merchant corrections

Same-filter reloads keep the loaded transaction list visible. Background SMS refreshes reuse current search/account/date filters, and the SMS review future is cached across unrelated parent rebuilds. No five-second UI timer was found; these changes address the identified spinner/requery paths. On-device confirmation of the reported periodic shiver remains outstanding.

Editing an existing transaction's nonempty merchant to another nonempty name now atomically renames matching history across accounts, using full-name matching with SQLite lower/trim (ASCII case folding). Similar substrings and blank merchants are excluded. Existing saved SMS rules with that display name follow the rename while retaining keyword/category/type. No new recognition rule is created automatically; Remember for future SMS still handles new rules. Amounts and categories of other records remain unchanged, and vector invalidation follows existing transaction triggers.

Validation: all 231 tests passed, including atomic rename/rollback and stable filtered refresh regressions. Static analysis passed. No APK build or device reproduction was performed for this update.

### Budget updates

Budget > bell and Settings > Budget updates provide independent morning plan, limit alerts and evening recap controls. Daily messages default off (08:00/21:00); existing limit notifications default on. Times must be ordered morning before evening. Notification permission is requested when enabling a control.

An Android Workmanager job checks every 15 minutes, recalculating from SQLCipher at delivery rather than scheduling stale amounts. It reads preferences afresh across isolates. Delivery is approximate and limited to a two-hour window (morning also stops at the evening time); outdated updates are skipped. Android force-stop, notification denial and battery restrictions can prevent delivery. Daily scheduling is disabled on iOS; this implementation has not added Apple background-task configuration. No network or AI inference is used for budget calculations.

Daily allowance = max(0, budget limit minus expenses recorded before today) / calendar days remaining, including today, rounded down to paise. Morning availability subtracts expenses already recorded today. Evening compares recorded spending to that same allowance and separately notes period overspending. Each budget is labelled by category, account scope and period; overlapping budgets are not added together. Future-dated entries and not-yet-started budgets are excluded. Weekly/monthly/yearly page calculations now use the same boundaries and scope as notifications.

Limit notifications now cover only 80% and 100%, with accurate over-budget wording. Multiple triggered budgets are combined into one notification. SQLCipher delivery claims prevent concurrent duplicate daily/threshold notifications; failed delivery releases claims for retry. Reaching 100% also consumes the earlier 80% warning. Schema 19 adds an auxiliary delivery log; logs are excluded from backup snapshots and cleared on reset/restore. Daily claims older than 35 days are pruned without pruning active long-period threshold claims. Existing legacy alert flags are respected.

Validation: 238 tests passed; static analysis clean. New tests cover paise allowances, final-day/overspend behavior, opt-in defaults, delivery windows, live/future-filtered figures, concurrent deduplication, failed-delivery retries, disabled updates, grouped thresholds and settings at normal/doubled text size. Background delivery on a physical phone still needs validation.

### Weekly recap, SMS correction, upcoming payments and goal progress

Weekly recap is available from the Insights calendar action. It compares the last complete Monday–Sunday week with the previous complete week, across all accounts, with exact date ranges and category deltas sorted by magnitude. Tapping a category opens its transactions for that week. Settings > Spending updates adds an optional Monday recap (09:00 default, configurable); the Budget bell opens the same controls. The existing Android background worker calculates it from the live ledger at delivery, respects opt-out/time windows, and uses atomic delivery claims. Notification taps open Weekly recap. No AI or financial advice is used.

SMS transaction row taps and queued SMS review now open a compact correction sheet for direction, amount, account, category and merchant. Unknown fields require explicit selection rather than a first-account guess. Saves await their own financial commit; errors keep the draft visible, and saving blocks repeated taps/dismissal. Existing SMS edits use atomic merchant history renaming. Optional Remember for future SMS opens the saved-rule editor after the transaction commits. Queue insertion/dedup/removal retain the existing atomic saveSms path. Other transaction entry flows remain available through their existing routes.

Home now summarizes reminders plus active subscriptions, with separate next-seven-day and overdue counts/totals and an All accounts label. Payments in More tools opens the combined view, with source management actions. Calendar recurrences are projected within the seven-day horizon; an overdue schedule remains a single item until handled. Inactive/distant items are excluded. Amounts represent scheduled records, not ledger expenses. Separate reminders/subscriptions are not heuristically merged if the user entered the same bill twice.

Goals display active/reached counts, recorded progress percentages, remaining amounts and a completion trophy. The contribution sheet owns its controllers, validates positive paise amounts, waits for persistence, and retains failed drafts. Feedback celebrates newly crossed 25/50/75% milestones or completion, with ordinary contributions showing remaining progress. Goal contributions affect only recorded goal savings; account balances and budget underspending are not automatically converted into savings. Repository contributions round to paise and reject invalid amounts or deleted goals.

Validation: all 249 Flutter tests passed; static analysis clean; Android debug ARM64 APK built. Eleven new tests cover completed-week totals and notification deduplication, schedule projection, goal milestones/account invariance, correction/contribution failure states, and normal/doubled text layouts. Rendered recap, payments, correction and goals previews were inspected. APK was not installed; real-device background notification delivery remains unverified.

### UI/UX consistency pass

More tools now has one Payments destination; the duplicate Subscriptions shortcut was removed. Subscriptions remain accessible inside Payments. Existing upcoming-payment summaries stay visible during source refreshes rather than disappearing while BLoCs reload.

SMS correction includes Edit all details. The handoff carries edited values and the future-SMS choice into the full editor, preserves the original persisted record for the update, and marks transferred edits dirty so Back still offers to retain/discard the draft. Neither the handoff nor opening the full editor commits a transaction. Correction sheets also respect bottom safe areas.

Spending updates shows a confirmed Notifications are off card with an Open settings action when system permission is blocked. Permission status is refreshed on app resume and after permission requests. Unsupported/unknown status is not presented as blocked; iOS provisional access is treated as allowed. Settings-launch failures remain visible. Notification permission is requested before registering newly enabled schedules.

Outlined actions use the shared border/radius/touch target; text/outlined actions have lighter readable foregrounds in dark mode, and muted dark text was lightened. New payment/recap list cards have consistent spacing. The transaction filter icon has an accessibility tooltip. This is a targeted consistency/accessibility pass, not a complete accessibility certification.

Validation: all 254 tests passed. Five additional regressions cover blocked permission at normal/doubled text sizes and resume, action-text contrast in both themes, unsaved quick-to-full editor handoff, and retained full-editor drafts. Normal layout previews were inspected. Real-device keyboard, notification delivery and screen-reader walkthroughs remain pending.

### Local file security extension

Retained receipts now use separate-key AES-256-GCM with in-memory display, verified legacy migration and encrypted restore. The native pending-SMS queue uses Android Keystore AES-GCM and atomic private-file writes, with verified SharedPreferences migration, stable retry identities and fail-closed key/tamper handling. Readable reports now use managed cache handoff files and cleanup; legacy SQLite validation files remain short-lived private-cache staging. Original gallery files and recipient-saved exports are outside app control. See docs/local-file-security.md for exact lifecycle, exceptions and limitations.

Validation: 262 Flutter tests passed; seven synthetic native checks passed in an isolated app on the connected Android phone; Android debug build passed. The native check app was uninstalled. Production user data was not inspected or migrated on the phone during these tests. Migration occurs when the updated app is launched. Static analysis passed.
