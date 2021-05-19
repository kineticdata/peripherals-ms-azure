## Azure API V1
The Azure REST API V1 is used to make Graph queries against the Azure AD service. 

### Parameters
Name | Description
----------- | -------------
Error Handling | Select between returning an error message, or raising an exception.
Method | HTTP Method to use for the Azure API call being made. <br/> Options are: GET, POST, PUT, DELETE
Path |  The relative API path is appened to 'https://graph.microsoft.com/v1.0'.  Visit [Microsoft Graph](https://developer.microsoft.com/) for more information on valid path configurations. This value should begin with a forward slash `/`.  
Body | The body content (JSON) that will be sent for POST, PUT, and PATCH requests.

### Results
Name | Description
----------- | -------------
Handler Error Message | Error message if an error was encountered and Error Handling is set to "Error Message".
Response Body | The returned value from the Rest Call (JSON format).
Response Code | The HTTP code returned from the request.

### Example inputs
Search for users that have a displayName that includes 'Chad'
```ruby
  'parameters' => {
    'error_handling' => 'Error Message',
    'headers' => '{"ConsistencyLevel": "eventual"}',
    'method' => 'GET',
    'path' => '/users?$search="displayName:Chad"',
    'body' => ''
  }
```
Get a list of groups in your organization
```ruby
  'parameters' => {
    'error_handling' => 'Error Message',
    'headers' => '',
    'method' => 'GET',
    'path' => '/groups',
    'body' => ''
  }
```
Add a user to a group
```ruby
  'parameters' => {
    'error_handling' => 'Error Message',
    'headers' => '',
    'method' => 'POST',
    'path' => '/groups/<:group-id>/members/$ref',
    'body' => '{"@odata.id": "https://graph.microsoft.com/v1.0/directoryObjects/<:user-id>"}'
  }
```

### Notes
 * The handler implicitly calls against the Microsoft Graph API v1.  The **path** parameter is append to: https://graph.microsoft.com/v1.0 
 * All requests are made using a bearer token.  The token is fetched on every execution of the handler. The token is received from a call to: https://login.microsoftonline.com/<:tenent_id>/oauth2/v2.0/token
 * The token's grant type is set to __client credentials__ with a scope of https://graph.microsoft.com/.default
 * Azure requires that an application be created to get assets from the system.  Visit [this article](https://www.inkoop.io/blog/how-to-get-azure-api-credentials/) for instructions on creating an application and getting values required for handler config.
 * It is likely the application will require permissions to access assets.  Visit [this article](https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-configure-app-access-web-apis#:~:text=client%20app's%20registration.-,Select%20Azure%20Active%20Directory%20%3E%20App%20registrations%2C%20and%20then%20select%20your,%3E%20Microsoft%20Graph%20%3E%20Application%20permissions.) for instructions on adding permissions.
