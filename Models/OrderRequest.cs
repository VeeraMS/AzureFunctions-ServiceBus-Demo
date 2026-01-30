namespace Ecommerce.Functions.Models;

/// <summary>
/// Incoming HTTP request model
/// </summary>
public class OrderRequest
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
}
