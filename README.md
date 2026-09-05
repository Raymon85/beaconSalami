# 🔗 BeaconSalami

A small, scalable link-shortener API — built as the semester project for the course **Skalbara molnapplikationer** (Scalable Cloud Applications).

Each week adds a new layer: app → cloud → automatic deployment → infrastructure as code → container → security. See [`TUTORIAL.md`](./docs/TUTORIAL.md) for the full step-by-step build log.

---

## ✨ What it does

| Endpoint | Method | Description |
|---|---|---|
| `/` | `GET` | Returns app name and status |
| `/health` | `GET` | Health check — always returns `200 OK` |
| `/shorten` | `POST` | Takes `{ "url": "..." }`, returns a short code |
| `/{code}` | `GET` | Redirects (`302`) to the original URL |

### Example

```bash
curl -X POST http://localhost:5001/shorten \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com/a/very/long/path"}'
# → {"code":"1","shortUrl":"/1"}

curl -i http://localhost:5001/1
# → 302 Found, Location: https://example.com/a/very/long/path
```

---

## 🛠️ Tech stack

- **.NET 10** minimal API (C#)
- **xUnit** for tests
- **Azure App Service** (Linux, B1) for hosting
- ⚠️ Storage is currently an in-memory `ConcurrentDictionary` — this is a **deliberate, temporary tradeoff**: it works on a single instance but not across multiple instances. A shared store (database/cache) is planned for a later stage of the course.

---

## 🚀 Running locally

```bash
cd src/BeaconSalami
dotnet run
```

The app listens on `http://localhost:5001` by default (check the terminal output for the exact port).

Run the tests:
```bash
dotnet test
```

---

## ☁️ Deployment

Runs on **Azure App Service** (Linux, B1), scaled to **3 instances**, with a health check on `/health`.

A `git push` to `main` automatically builds, tests, and deploys the app via GitHub Actions (`.github/workflows/deploy.yml`), followed by a post-deployment smoke test (`scripts/health-check.sh`) that confirms the app actually responds before the pipeline is marked successful.

See [`TUTORIAL.md`](./docs/TUTORIAL.md) for the full reasoning behind every decision —