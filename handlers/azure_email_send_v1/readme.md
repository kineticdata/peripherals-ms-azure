## Azure Email Send V1
Sends an email through the Microsoft Graph API `sendMail` endpoint as an Exchange Online mailbox.

### Info Values
Name | Description
----------- | -------------
tenant_id | Azure Directory (Tenant) Id. Either the GUID or a domain such as `contoso.onmicrosoft.com`.
client_id | Application (Client) Id of the Azure app registration.
client_secret | Client secret of the Azure app registration. Use the secret's **Value**, not its Secret ID.
from_address | Default sender mailbox (e.g. `noreply@contoso.com`). Used when From (Override) is blank.
enable_debug_logging | True or False.

### Parameters
Name | Description
----------- | -------------
Error Handling | Select between returning an error message, or raising an exception.
From (Override) | Optional sender mailbox to use instead of the configured `from_address`.
To | Comma or semicolon separated list of addresses.
CC | Comma or semicolon separated list of addresses.
BCC | Comma or semicolon separated list of addresses.
Subject | Subject of the email. Required.
HTML Body | HTML content of the email.
Text Body | Plain text content of the email. **Only used when HTML Body is blank.**

Addresses can be plain (`jane@example.com`) or include a display name (`Jane Doe <jane@example.com>`,
`"Doe, Jane" <jane@example.com>`). Duplicate addresses within a field are removed. At least one recipient
is required across To, CC, and BCC, so a BCC-only send is allowed.

### Results
Name | Description
----------- | -------------
Response Code | The HTTP code of the last request made. `202` when the email was accepted by Microsoft Graph.
From Address | The sender mailbox that was used (the override if provided, otherwise `from_address`).
Handler Error Message | Error message if an error was encountered and Error Handling is set to "Error Message".

### Example inputs
Send an HTML email using the configured sender
```ruby
  'parameters' => {
    'error_handling' => 'Error Message',
    'from_override' => '',
    'to' => 'Jane Doe <jane.doe@example.com>, john.smith@example.com',
    'cc' => '',
    'bcc' => '',
    'subject' => 'Your request has been approved',
    'html_body' => '<p>Your request <strong>REQ-1001</strong> has been approved.</p>',
    'text_body' => ''
  }
```
Send a plain text email from a different mailbox
```ruby
  'parameters' => {
    'error_handling' => 'Error Message',
    'from_override' => 'helpdesk@contoso.com',
    'to' => 'jane.doe@example.com',
    'cc' => 'manager@example.com',
    'bcc' => 'audit@example.com',
    'subject' => 'Ticket INC-2002 updated',
    'html_body' => '',
    'text_body' => 'Your ticket has been updated.'
  }
```

### HTML Body and Text Body
Microsoft Graph's `sendMail` JSON format allows a single body per message, either HTML or Text. It does not
send a multipart/alternative message containing both.
 * If **HTML Body** has content, it is sent and **Text Body is ignored**, even if Text Body also has content.
 * If HTML Body is blank, Text Body is sent as plain text.
 * At least one of the two must have content.

### Azure Setup
 1. Create an app registration in Azure (Microsoft Entra ID) and create a client secret for it.
 2. Under **API permissions**, add the Microsoft Graph **Application** permission `Mail.Send` (not the
    Delegated permission) and **grant admin consent**.
 3. The sender (`from_address` or From (Override)) must be an Exchange Online user or shared mailbox in the
    same tenant.
 4. **Restrict which mailboxes the app can send as.** By default, the `Mail.Send` application permission
    allows the app to send as *any* mailbox in the tenant. Use Exchange Online
    [RBAC for Applications](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac)
    (or the older Application Access Policies) to limit the app to the intended sender mailbox(es). This is
    the recommended control for which addresses the From (Override) input can use.

### Error Handling
Inputs are validated before any network call, and every problem found is reported in one message (for
example, every invalid address across To, CC, and BCC). Errors from Azure AD and Microsoft Graph are
translated into a description of the likely cause and fix, followed by the raw details for support:
```
The app is not allowed to send mail as noreply@contoso.com. Make sure the app registration has the
Mail.Send application permission with admin consent granted, ... (Graph: ErrorAccessDenied - Access is
denied. Check credentials and try again.; HTTP 403; request-id: 6a1c...)
```
Include the `request-id` (Graph) or `correlation-id` (Azure AD) when opening a case with Microsoft.

When Error Handling is "Raise Error", the same message is raised instead of returned.

### Notes
 * An access token is fetched on every execution from
   `https://login.microsoftonline.com/<tenant_id>/oauth2/v2.0/token` using the client credentials grant with
   a scope of `https://graph.microsoft.com/.default`.
 * The email is sent with `POST https://graph.microsoft.com/v1.0/users/<sender>/sendMail` and a copy is
   saved to the sender's Sent Items.
 * Graph does not return a message id for `sendMail`. A `202` response means the message was accepted for
   delivery.
 * Exchange Online allows at most 500 recipients (To + CC + BCC) per message.
 * When Graph responds with `429` (throttled) or `503` (unavailable), the send is retried up to 3 times,
   waiting for the `Retry-After` time (capped at 30 seconds).
 * Timeouts and dropped connections while sending are **not** retried, because the email may already have
   been sent. The error message says so; check the sender's Sent Items before running the task again.
 * Debug logging never writes the client secret, access token, recipient addresses, or body content.
 * Attachments are not supported in this version.
 * The handler uses only the Ruby standard library (no bundled gems).
