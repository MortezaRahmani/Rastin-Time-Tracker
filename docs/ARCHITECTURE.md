# RTT architecture

```text
Flutter app (Android + Windows/macOS/Linux)
  ├─ UI: timer, projects, activity history, reports, settings
  ├─ local SQLite 3 database (the app is fully usable offline)
  └─ optional sync client ── HTTPS JSON ── PHP 8 API ── SQLite 3
                                                 └─ personal sync database
```

One Flutter application is the client. The PHP application is a small HTTP API with no framework and is only required for online mode. Each user has one personal dataset; it is not a collaboration or multi-user product.

The client owns the domain model and local database. The server validates and stores sync records; it does not calculate reports. This keeps offline use, cPanel deployment, and future installer builds simple.
