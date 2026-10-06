using System.Collections.Concurrent;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// In-memory store: code -> original URL.
// NOTE: this only works correctly on a single instance. With 3+ instances
// behind the load balancer, a link created on instance A won't be visible
// on instance B. This is a conscious, temporary tradeoff — see week 39
// (delad databas / cache) for the real fix. Documented in TUTORIAL.md.
var links = new ConcurrentDictionary<string, string>();
var counter = 0;

// NEW: each instance/replica has a unique name. Azure sets these env vars for us.
var instanceId =
    Environment.GetEnvironmentVariable("CONTAINER_APP_REPLICA_NAME")   // Container Apps
    ?? Environment.GetEnvironmentVariable("WEBSITE_INSTANCE_ID")       // App Service
    ?? Environment.MachineName;                                        // local

// NEW: add the instance id as a header on EVERY response (200, 302, 404...).
app.Use(async (ctx, next) =>
{
    ctx.Response.Headers["X-Instance-Id"] = instanceId;
    await next();
});

app.MapGet("/", () => new
{
    app = "BeaconSalami",
    status = "running"
});

// Health check. Used by App Service (week 35), by health-check.sh (week 36)
// and by the container (week 38). Do not remove.
app.MapGet("/health", () => Results.Ok("OK"));

// NEW: shows which instance answered and how many links it holds in memory.
app.MapGet("/instance", () => Results.Ok(new { instance = instanceId, links = links.Count }));

// POST /shorten  { "url": "https://example.com/very/long/path" }
// -> { "code": "3", "shortUrl": "/3" }
app.MapPost("/shorten", (ShortenRequest request) =>
{
    if (string.IsNullOrWhiteSpace(request.Url) ||
        !Uri.TryCreate(request.Url, UriKind.Absolute, out _))
    {
        return Results.BadRequest(new { error = "Provide a valid absolute URL." });
    }

    var code = Interlocked.Increment(ref counter).ToString();
    links[code] = request.Url;

    return Results.Ok(new { code, shortUrl = $"/{code}" });
});

// GET /{code} -> 302 redirect to the original URL, or 404 if unknown.
app.MapGet("/{code}", (string code) =>
{
    return links.TryGetValue(code, out var url)
        ? Results.Redirect(url)
        : Results.NotFound(new { error = $"No link found for code '{code}'." });
});

app.Run();

record ShortenRequest(string Url);

// Makes Program visible to the test project.
public partial class Program { }