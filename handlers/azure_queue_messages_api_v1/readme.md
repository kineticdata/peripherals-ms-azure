## Azure Queue Message API V1
Used to Create or Retrieve queue messages from the Azure Rest endpoints.

### Parameters
Name | Description
----------- | -------------
Error Handling | Select between returning an error message, or raising an exception.
Method | HTTP Method to use for the Azure API call being made. <br/> Options are: GET, POST, PUT, DELETE
Storage Account | Azure high level namespace
Path |  The relative API path is appended to 'https://<storage_account>.queue.core.windows.net'.  Visit [Microsoft Queue Messages](https://docs.microsoft.com/en-us/rest/api/storageservices/operations-on-messages) for more information on valid path configurations. This value should begin with a forward slash `/`.  
Body | The body content that will be sent for POST and PUT requests. !Do not encode Base 64 the input as the handler preforms this task.

### Results
Name | Description
----------- | -------------
Handler Error Message | Error message if an error was encountered and Error Handling is set to "Error Message".
Response Body Raw | The returned value from the Rest Call (XML format).
Messages Array | An array of JSON formatted message objects.
Response Code | The HTTP code returned from the request.

### Example inputs
Get four messages for the <foo> queue
```ruby
  'parameters' => {
    'error_handling' => 'Error Message',
    'headers' => '',
    'method' => 'GET',
    'path' => '/<foo>/messages?numofmessages=4',
    'body' => ''
  }
```
Delete a message for the <foo> queue
```ruby
  'parameters' => {
    'error_handling' => 'Error Message',
    'headers' => '',
    'method' => 'DELETE',
    'path' => '/<foo>/messages/<message id>?popreceipt=<pop receipt id>',
    'body' => ''
  }
```
Update an existing message for the <foo> queue
```ruby
  'parameters' => {
    'error_handling' => 'Error Message',
    'headers' => '',
    'method' => 'PUT',
    'path' => '/<foo>/messages/<message id>?popreceipt=<pop receipt id>',
    'body' => 'Update to message'
  }
```
## Azure Requirements
  1. [Register a new app](https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-register-app) in Azure portal.
  2. Get [Client Id, Tenant Id, and Client Secret](https://support.lacework.com/hc/en-us/articles/360029107274-Gather-the-Required-Azure-Client-ID-Tenant-ID-and-Client-Secret) for use with handler configuration.
    * Create a [Client Secret](https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal#option-2-create-a-new-application-secret) for your app if one does not exist.
  3. [Create a Storage Account](https://docs.microsoft.com/en-us/azure/storage/common/storage-account-create?tabs=azure-portal).
  4. [Create a Queue](https://docs.microsoft.com/en-us/azure/storage/queues/storage-quickstart-queues-portal).
  5. !!Important: The app will need to be granted IAM permissions for the storage account.
    * Select storage accounts from Azure portal.
    * Select the storage account that has the queue to interact with.
    * Select **Access Control (IAM)**.
    * Select **+ Add** to add a role assignment.
    * Add Reader and Storage Account Contributor roles (Will have to do individually).
    * Select registered app from the members list.
    * **Review + assign**.

### Notes
 * The **path** parameter is append to: https://<storage_account>.queue.core.windows.net 
 * All requests are made using a bearer token.  The token is fetched on every execution of the handler. The token is received from a call to: https://login.microsoftonline.com/<tenent_id>/oauth2/v2.0/token
 * The token's grant type is set to __client credentials__ with a scope of https://<storage_account>.queue.core.windows.net/.default  
