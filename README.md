# Azure Function - Service Bus Demo

A demonstration Azure Function that receives HTTP requests and sends messages to Azure Service Bus.

## Architecture

```
HTTP Request              Azure Function              Service Bus Queue
    │                          │                            │
    │  POST /api/ProcessOrder  │                            │
    │  {"Id":"123",            │                            │
    │   "Name":"Product"}      │                            │
    │ ─────────────────────────▶                            │
    │                          │  Maps to:                  │
    │                          │  {"TransactionId":"123",   │
    │                          │   "ProductName":"Product", │
    │                          │   "CreatedAt":"..."}       │
    │                          │ ─────────────────────────▶ │
    │                          │                            │
    │ ◀─────────────────────── │                            │
    │  Response: Success       │                            │
```

## Functions

| Function | Trigger | Description |
|----------|---------|-------------|
| `ProcessOrderTrigger` | HTTP POST | Receives order, sends to Service Bus |
| `ProcessOrderFromQueue` | Service Bus | Processes messages from queue |

## Data Models

### Input (HTTP Request)
```json
{
  "Id": "ORD-12345",
  "Name": "Laptop Pro X1"
}
```

### Output (Service Bus Message)
```json
{
  "TransactionId": "ORD-12345",
  "ProductName": "Laptop Pro X1",
  "CreatedAt": "2026-01-30T08:11:31Z"
}
```

## Prerequisites

- [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Azure Functions Core Tools v4](https://docs.microsoft.com/azure/azure-functions/functions-run-local)
- [Docker Desktop](https://www.docker.com/products/docker-desktop) (for local Service Bus emulator)

## Local Development Setup

### 1. Clone and Setup
```bash
git clone <repo-url>
cd FunctionAppDemos
cp local.settings.sample.json local.settings.json
```

### 2. Start Service Bus Emulator
```bash
docker-compose up -d
```

This starts:
- **SQL Edge** - Metadata storage for emulator
- **Service Bus Emulator** - Local Service Bus with "orders" queue

### 3. Build and Run
```bash
dotnet build
cd bin/Debug/net8.0
func host start
```

### 4. Test the Function
```powershell
$body = @{Id="ORD-12345"; Name="Laptop Pro X1"} | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:7071/api/ProcessOrderTrigger" -Method POST -Body $body -ContentType "application/json"
```

### 5. View Messages in Queue
```bash
cd Tools/MessageViewer
dotnet run
```

## Project Structure

```
FunctionAppDemos/
├── ProcessOrderTrigger.cs      # HTTP trigger → Service Bus output
├── ProcessOrderFromQueue.cs    # Service Bus trigger (consumer)
├── Program.cs                  # Function app entry point
├── Models/
│   ├── OrderRequest.cs         # Input model
│   └── ServiceBusOrderMessage.cs # Output model
├── Tools/
│   └── MessageViewer/          # Console app to peek queue messages
├── docker-compose.yml          # Service Bus Emulator setup
├── servicebus-config.json      # Emulator queue configuration
└── local.settings.sample.json  # Template for local settings
```

## Configuration

### Local Development (Emulator)
```json
{
  "ServiceBusConnection": "Endpoint=sb://localhost;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=SAS_KEY_VALUE;UseDevelopmentEmulator=true;"
}
```

### Azure (Connection String)
```json
{
  "ServiceBusConnection": "Endpoint=sb://your-namespace.servicebus.windows.net/;SharedAccessKeyName=...;SharedAccessKey=..."
}
```

### Azure (Managed Identity)
```json
{
  "ServiceBusConnection__fullyQualifiedNamespace": "your-namespace.servicebus.windows.net"
}
```

## Useful Commands

| Command | Description |
|---------|-------------|
| `docker-compose up -d` | Start Service Bus Emulator |
| `docker-compose down` | Stop emulator |
| `docker logs servicebus-emulator` | View emulator logs |
| `func host start` | Run Azure Functions locally |
| `dotnet build` | Build the project |

## License

MIT
