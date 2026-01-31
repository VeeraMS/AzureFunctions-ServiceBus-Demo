using Azure.Identity;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.Azure;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWebApplication();

// ============================================================================
// STEP 2: Register Azure Service Bus Client using Dependency Injection
// ============================================================================
// Environment-aware configuration:
// - LOCAL: Uses connection string from local.settings.json (emulator)
// - AZURE: Uses Managed Identity with namespace URL
// ============================================================================

builder.Services.AddAzureClients(clientBuilder =>
{
    // Check if we have a connection string (local development with emulator)
    var connectionString = builder.Configuration["ServiceBusConnection"];
    
    // Check if we have a fully qualified namespace (Azure with Managed Identity)
    var fullyQualifiedNamespace = builder.Configuration["ServiceBusConnection__fullyQualifiedNamespace"];
    
    if (!string.IsNullOrEmpty(connectionString) && !connectionString.Contains("fullyQualifiedNamespace"))
    {
        // LOCAL: Use connection string (emulator or local Service Bus)
        Console.WriteLine("🔧 Using Service Bus CONNECTION STRING (local/emulator)");
        clientBuilder.AddServiceBusClient(connectionString);
    }
    else if (!string.IsNullOrEmpty(fullyQualifiedNamespace))
    {
        // AZURE: Use Managed Identity with namespace
        Console.WriteLine($"☁️ Using Service Bus MANAGED IDENTITY: {fullyQualifiedNamespace}");
        clientBuilder.AddServiceBusClientWithNamespace(fullyQualifiedNamespace);
        clientBuilder.UseCredential(new DefaultAzureCredential());
    }
    else
    {
        // Fallback: hardcoded namespace (not recommended for production)
        Console.WriteLine("⚠️ Fallback: Using hardcoded namespace with DefaultAzureCredential");
        clientBuilder.AddServiceBusClientWithNamespace("sbordersdemoin.servicebus.windows.net");
        clientBuilder.UseCredential(new DefaultAzureCredential());
    }
});

// Register ServiceBusSender as singleton for the "orders" queue
builder.Services.AddSingleton(sp =>
{
    var client = sp.GetRequiredService<ServiceBusClient>();
    return client.CreateSender("orders");
});

builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

builder.Build().Run();
