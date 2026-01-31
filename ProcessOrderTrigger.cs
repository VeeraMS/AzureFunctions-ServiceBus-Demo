using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Ecommerce.Functions.Models;

namespace Ecommerce.Functions;

public class ProcessOrderTrigger
{
    private const string AppVersion = "2.0.0";  // Version for tracking deployments
    private readonly ILogger<ProcessOrderTrigger> _logger;
    private readonly ServiceBusSender _serviceBusSender;

    // ============================================================================
    // STEP 3: Constructor Injection
    // ============================================================================
    // ServiceBusSender is injected by DI (registered in Program.cs)
    // - Already configured for "orders" queue
    // - Uses Managed Identity authentication
    // - Singleton instance (connection reused across requests)
    // ============================================================================
    public ProcessOrderTrigger(ILogger<ProcessOrderTrigger> logger, ServiceBusSender serviceBusSender)
    {
        _logger = logger;
        _serviceBusSender = serviceBusSender;
    }

    /// <summary>
    /// HTTP Trigger that receives an order request and sends a message to Service Bus
    /// Input: {"Id":"...","Name":"..."}
    /// Output: {"success":true,"messageId":"...","transactionId":"...","productName":"...","createdAt":"..."}
    /// </summary>
    [Function("ProcessOrderTrigger")]
    public async Task<IActionResult> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post")] HttpRequest req)
    {
        _logger.LogInformation("🚀 ProcessOrderTrigger v{Version} - Processing order request...", AppVersion);

        try
        {
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
                return new BadRequestObjectResult(new 
                { 
                    success = false,
                    error = "Invalid request: Id and Name are required" 
                });
            }

            _logger.LogInformation("Received order - Id: {Id}, Name: {Name}", orderRequest.Id, orderRequest.Name);

            // STEP 4: Create Service Bus message with unique MessageId
            var serviceBusMessage = new ServiceBusOrderMessage
            {
                MessageId = Guid.NewGuid().ToString(),
                TransactionId = orderRequest.Id,
                ProductName = orderRequest.Name,
                CreatedAt = DateTime.UtcNow
            };

            // STEP 5: Serialize to JSON
            var messageJson = JsonSerializer.Serialize(serviceBusMessage);
            _logger.LogInformation("Service Bus Message: {Message}", messageJson);

            // STEP 6: Send to Service Bus using injected sender
            var message = new ServiceBusMessage(messageJson)
            {
                MessageId = serviceBusMessage.MessageId,
                ContentType = "application/json"
            };
            
            await _serviceBusSender.SendMessageAsync(message);
            _logger.LogInformation("Message sent to Service Bus successfully. MessageId: {MessageId}", serviceBusMessage.MessageId);

            // STEP 7: Return success response with full details
            return new OkObjectResult(new 
            { 
                success = true,
                version = AppVersion,  // Added version to track which slot is serving
                message = "Order queued successfully",
                queueName = "orders",
                messageId = serviceBusMessage.MessageId,
                transactionId = serviceBusMessage.TransactionId,
                productName = serviceBusMessage.ProductName,
                createdAt = serviceBusMessage.CreatedAt
            });
        }
        catch (ServiceBusException sbEx)
        {
            // Handle Service Bus specific errors
            _logger.LogError(sbEx, "Service Bus error: {Message}", sbEx.Message);
            return new ObjectResult(new 
            { 
                success = false,
                error = "Failed to queue order",
                details = sbEx.Reason.ToString()
            }) 
            { 
                StatusCode = StatusCodes.Status503ServiceUnavailable 
            };
        }
        catch (Exception ex)
        {
            // Handle unexpected errors
            _logger.LogError(ex, "Unexpected error: {Message}", ex.Message);
            return new ObjectResult(new 
            { 
                success = false,
                error = "Internal server error"
            }) 
            { 
                StatusCode = StatusCodes.Status500InternalServerError 
            };
        }
    }
}