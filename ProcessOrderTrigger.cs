using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Ecommerce.Functions.Models;

namespace Ecommerce.Functions;

/// <summary>
/// Output class for multiple return values (HTTP response + Service Bus message)
/// </summary>
public class ProcessOrderOutput
{
    /// <summary>
    /// SERVICE BUS OUTPUT BINDING:
    /// - "orders" = Queue name
    /// - Connection = Name of connection string in local.settings.json
    /// When function returns, runtime reads this property and sends to Service Bus
    /// </summary>
    [ServiceBusOutput("orders", Connection = "ServiceBusConnection")]
    public string? ServiceBusMessage { get; set; }

    /// <summary>
    /// HTTP Response returned to the caller
    /// </summary>
    public IActionResult? HttpResponse { get; set; }
}

public class ProcessOrderTrigger
{
    private readonly ILogger<ProcessOrderTrigger> _logger;

    public ProcessOrderTrigger(ILogger<ProcessOrderTrigger> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// HTTP Trigger that receives an order request and sends a message to Service Bus
    /// Input: {"Id":"...","Name":"..."}
    /// Output: {"TransactionId":"...","ProductName":"...","CreatedAt":"...","MessageId":"..."}
    /// </summary>
    [Function("ProcessOrderTrigger")]
    public async Task<ProcessOrderOutput> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post")] HttpRequest req)
    {
        _logger.LogInformation("Processing order request...");

        // STEP 1: Read HTTP request body
        string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
        
        // STEP 2: Deserialize JSON to OrderRequest model
        var orderRequest = JsonSerializer.Deserialize<OrderRequest>(requestBody, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        });

        // STEP 3: Validate input
        if (orderRequest == null || string.IsNullOrEmpty(orderRequest.Id) || string.IsNullOrEmpty(orderRequest.Name))
        {
            _logger.LogWarning("Invalid request: Id and Name are required");
            return new ProcessOrderOutput
            {
                HttpResponse = new BadRequestObjectResult("Invalid request: Id and Name are required"),
                ServiceBusMessage = null  // Don't send to Service Bus on error
            };
        }

        _logger.LogInformation("Received order - Id: {Id}, Name: {Name}", orderRequest.Id, orderRequest.Name);

        // STEP 4: MAP input to Service Bus message format with unique MessageId
        var serviceBusMessage = new ServiceBusOrderMessage
        {
            MessageId = Guid.NewGuid().ToString(),
            TransactionId = orderRequest.Id,
            ProductName = orderRequest.Name,
            CreatedAt = DateTime.UtcNow
        };

        // STEP 5: Serialize to JSON for Service Bus
        var messageJson = JsonSerializer.Serialize(serviceBusMessage);
        _logger.LogInformation("Service Bus Message: {Message}", messageJson);

        // STEP 6: Return output - Azure Functions runtime will:
        //   a) Send HttpResponse back to HTTP caller
        //   b) Send ServiceBusMessage to the "orders" queue (AUTOMATICALLY!)
        return new ProcessOrderOutput
        {
            HttpResponse = new OkObjectResult(new 
            { 
                Success = true,
                Message = "Message successfully sent to Service Bus",
                QueueName = "orders",
                MessageId = serviceBusMessage.MessageId,
                TransactionId = serviceBusMessage.TransactionId,
                ProductName = serviceBusMessage.ProductName,
                CreatedAt = serviceBusMessage.CreatedAt
            }),
            ServiceBusMessage = messageJson
        };
    }
}