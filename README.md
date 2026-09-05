# 🔗 BeaconSalami

A small, scalable link-shortener API — built as the semester project for the course **Skalbara molnapplikationer** (Scalable Cloud Applications).

Each week adds a new layer: app → cloud → automatic deployment → infrastructure as code → container → security. See [`TUTORIAL.md`](./TUTORIAL.md) for the full step-by-step build log.

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

Currently deployed manually to Azure App Service via:
```bash
az webapp up \
  --name app-clo25-rayan \
  --resource-group rg-clo25-rayan \
  --runtime "DOTNETCORE:10.0" \
  --sku B1 \
  --location swedencentral \
  --os-type linux
```

Running on **3 instances** with a health check on `/health`. Automatic CI/CD via GitHub Actions is planned for a later week — see [`TUTORIAL.md`](./TUTORIAL.md) for details and reasoning behind every decision.

---

## 📁 Project structure

```
src/BeaconSalami/       — the app
tests/BeaconSalami.Tests/ — unit tests
TUTORIAL.md              — full build log, week by week
requests.http             — manual test requests
```
