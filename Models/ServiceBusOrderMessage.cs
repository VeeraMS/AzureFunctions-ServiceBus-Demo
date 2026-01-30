namespace Ecommerce.Functions.Models;

/// <summary>
/// Service Bus message model - maps from OrderRequest
/// </summary>
public class ServiceBusOrderMessage
{
    /// <summary>
    /// Mapped from OrderRequest.Id
    /// </summary>
    public string TransactionId { get; set; } = string.Empty;

    /// <summary>
    /// Mapped from OrderRequest.Name
    /// </summary>
    public string ProductName { get; set; } = string.Empty;

    /// <summary>
    /// Timestamp when the message was created
    /// </summary>
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
