var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => new
{
    app = "BeaconSalami",
    status = "running"
});

// Health check. Used by App Service (week 35), by health-check.sh (week 36)
// and by the container (week 38). Do not remove.
app.MapGet("/health", () => Results.Ok("OK"));

app.Run();

// Makes Program visible to the test project.
public partial class Program { }