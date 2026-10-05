## Azure Notification Template Send V1
Builds an email from a notification template stored in the Kinetic Platform and sends it through the Microsoft
Graph API as an Exchange Online mailbox. Templates can include snippets, replacement values, formatted dates,
inline images, and file attachments from both the template and a related submission.

### Info Values
Name | Description
----------- | -------------
tenant_id | Azure Directory (Tenant) Id. Either the GUID or a domain such as `contoso.onmicrosoft.com`.
client_id | Application (Client) Id of the Azure app registration.
client_secret | Client secret of the Azure app registration. Use the secret's **Value**, not its Secret ID.
azure_cloud | Microsoft cloud of the tenant: `Global` (default), `GCC High`, `DoD`, or `China`. GCC (Moderate) tenants use `Global`. See Microsoft Clouds.
from_address | Default sender mailbox (e.g. `noreply@contoso.com`). Used when From (Override) is blank.
api_server | Kinetic Platform server URL, e.g. `https://server/kinetic` or `https://my-space.kinops.io`. If it contains `${space}`, that is replaced with the space slug; otherwise a space slug, when provided, is appended as `/<space slug>`.
api_username | Kinetic user with access to the notification forms and to the related submissions.
api_password | Password for the Kinetic user.
space_slug | Default space slug, used when the Space Slug input is blank.
kapp_slug | Kapp containing the notification forms. Default `datastore`.
form_slug_data | Form holding notification templates and snippets. Default `notification-data`.
form_slug_dates | Form holding date formats. Default `notification-template-dates`.
template_attachments_field | Attachment field on the template form whose files are sent with every email that uses the template. Default `Email Template Attachments`. Leave blank if templates do not have attachments.
max_attachment_size_mb | Maximum total size, in MB, of attachments and inline images in one email. Default `25`.
enable_debug_logging | True or False.

### Parameters
Name | Description
----------- | -------------
Error Handling | Select between returning an error message, or raising an exception.
Space Slug | Space containing the notification templates. Blank uses the space_slug property.
Recipient Json Object | The recipient's addresses and preferences (see below), or an email address.
Notification Template Name | Name of an Active notification template.
Replacement Values | JSON object of values used for `${key('name')}` replacements (see below). Optional.
Submission Id | Submission whose attachment fields are referenced by the template's Attachments field. Required only when the template references submission attachments.
From (Override) | Sender mailbox to use instead of from_address. Optional.

#### Recipient Json Object
```json
{
  "smtpaddress": {
    "to": "jane.doe@example.com, John Smith <john.smith@example.com>",
    "cc": "manager@example.com",
    "bcc": "audit@example.com"
  },
  "language": "en",
  "region": "",
  "email notifications": "yes"
}
```
 * `to`, `cc`, and `bcc` are comma or semicolon separated lists. Display names are supported. A JSON array of
   addresses also works. At least one address is required across the three.
 * `smtpaddress` can also be a single string, which is used as `to`.
 * The whole value can be a plain address or address list instead of JSON, which is used as `to`.
 * `language` and `region` select between templates that share a name (see Templates).
 * When `email notifications` is `no` (or `false`), no email is sent and the handler returns Status `Skipped`
   with no error.

### Results
Name | Description
----------- | -------------
Handler Error Message | Error message if an error was encountered and Error Handling is set to "Error Message". Empty when the handler succeeds or skips.
Email Id | The Internet message id of the sent email, when one is available (see How the Email Is Sent).
Status | `Sent`, `Skipped` (the recipient has email notifications turned off), or `Failed`.
From Address | The sender mailbox used.
Attachment Count | Number of files attached, not counting inline images.
Response Code | HTTP code of the last response received. `202` when the email was accepted. Empty when the handler stopped before receiving a response (for example, when an input or the template failed validation).

### Templates
Templates and snippets are records in the `form_slug_data` form. The handler uses these fields:

Field | Use
----------- | -------------
Name | Matched against Notification Template Name or a snippet name.
Status | Only `Active` records are used.
Language, Region | When several active records share a name, the record matching the recipient's language and region is used (both match, then language, then region; otherwise the first record).
Subject | Email subject. Required.
HTML Content | HTML body.
Text Content | Plain text body.
Attachments | `${attachment('Field Name')}` references to attachment fields on the related submission.
*template_attachments_field* | The attachment field named by the template_attachments_field property (default `Email Template Attachments`). Its files are sent with every email that uses the template.

**Body:** if HTML Content has content after processing, it is sent as the body and Text Content is not sent.
If HTML Content is blank, Text Content is sent as plain text. At least one must have content.

Content is processed in this order:

 1. **Snippets.** `${snippet('Name')}` is replaced with the snippet's HTML Content (in HTML Content) or Text
    Content (in Subject and Text Content). Snippets can contain snippets, up to 10 levels deep.
 2. **Replacements.** `${key('name')}` is replaced with `Replacement Values[key][name]`, for every key in
    Replacement Values, for example `${values('Summary')}`, `${form('Form Name')}`, `${vars('x')}`.
    * `null` becomes empty, a list becomes a comma separated list, and other objects become JSON.
    * A placeholder with no matching value is left in the content as written. With debug logging on, these
      are listed in the log.
 3. Steps 1 and 2 run a second time, so snippets and replacements that come from replacement values are also
    processed.
 4. **Dates.** `${appearance('<date>${format('<Format Name>')}')}` formats a date using the Format of the
    active record named `<Format Name>` in the `form_slug_dates` form. The Format is a Ruby strftime pattern,
    such as `%B %-d, %Y`. Example: `${appearance('${submission('submittedAt')}${format('Long Date')}')}`.
    A blank or unparseable date is left as provided. Timestamps are formatted in the time zone they are written
    in (UTC for Kinetic timestamps).
 5. **Inline images.** Each `"cid:<http(s) URL>"` in HTML Content, such as `<img src="cid:https://host/logo.png">`,
    is downloaded and embedded in the email as an inline image.

### Attachments
An email can include files from two sources, and a template can use both:

 * **Template attachments.** Every file in the template record's attachment field named by the
   template_attachments_field property (default `Email Template Attachments`) is sent automatically. Nothing needs to
   be added to the template's Attachments field, and no Submission Id is needed. If the property names a field
   that is not on the template form, the handler fails with an error naming the property. When the property is
   blank, template attachments are not used.
 * **Submission attachments.** For each `${attachment('Field Name')}` in the template's **Attachments** field,
   every file in that attachment field of the submission given by Submission Id is sent. The Attachments field
   is only for submission fields. An attachment field that exists but has no files is skipped.

> **Special note on attachment field names:** an `${attachment('...')}` entry in the Attachments field that
> names the template attachments field (the template_attachments_field value, for example
> `${attachment('Email Template Attachments')}`) is ignored, since those files are already sent automatically.
> As a result, a field on the related submission with that same name cannot be attached. Give submission
> attachment fields names that differ from the template attachments field. When template_attachments_field is
> blank, no entries are ignored.

Whether a field exists is decided by the form's definition, so a field added to a form after a record was
saved is treated as empty on that record rather than missing.

Files are downloaded through the Kinetic Platform API. The api_username and api_password are only sent to
the api_server host.

**Size limit:** the total of all attachments and inline images cannot be more than max_attachment_size_mb
(default 25 MB). The handler checks the sizes recorded in Kinetic before downloading anything, and checks again
after downloading. When the limit is exceeded, the error lists each file and its size. Attachments grow by
about a third when an email is sent, and Exchange Online's default maximum message size is 35 MB, so 25 MB is
close to the largest total most mailboxes accept.

### How the Email Is Sent
An access token is fetched on every execution from
`https://<sign-in host>/<tenant_id>/oauth2/v2.0/token` (client credentials, scope `https://<Graph host>/.default`),
and Graph requests go to `https://<Graph host>/v1.0`, where the hosts come from azure_cloud (see Microsoft
Clouds). A copy of each email is saved to the sender's Sent Items. The handler
uses one of two methods, based on the size of the request:

 * **Single request.** When the message and its base64 encoded attachments add up to about 3.5 MB or less
   (which includes every email without attachments), the email is sent with one
   `POST /users/<sender>/sendMail` request. Microsoft Graph does not return a message id for this request, so
   Email Id is empty.
 * **Draft.** Larger emails are built as a draft and then sent:
    1. `POST /users/<sender>/messages` creates the draft. Its Internet message id is returned as Email Id.
    2. Each file under 3 MB is added with `POST .../attachments`. Larger files are uploaded in chunks of about
       3 MB through an upload session (`POST .../attachments/createUploadSession`, then `PUT` to the upload URL).
    3. `POST .../messages/<id>/send` sends the draft.

   If any step fails before the send, the draft is deleted, and the error message says whether that worked.
   If the send itself times out, the draft is kept because the email may have gone out. The error says to check
   the Sent Items and Drafts folders.

### Microsoft Clouds
The azure_cloud property selects the Microsoft sign-in and Graph endpoints for the tenant's cloud. Tokens from
one cloud are not accepted by another, so it must match the cloud where the tenant and app registration live.

azure_cloud | Sign-in host | Graph host
----------- | ------------- | -------------
Global (default) | `login.microsoftonline.com` | `graph.microsoft.com`
GCC High | `login.microsoftonline.us` | `graph.microsoft.us`
DoD | `login.microsoftonline.us` | `dod-graph.microsoft.us`
China | `login.chinacloudapi.cn` | `microsoftgraph.chinacloudapi.cn`

 * GCC (Moderate) tenants use `Global`. `GCC` and `GCC Moderate` are accepted as other names for `Global`.
 * Case, spaces, hyphens, and underscores are ignored, so `gcc-high` and `GCCHigh` both mean GCC High. Any other
   value fails before anything is sent.
 * When Microsoft returns an error that a cloud mismatch can cause (for example, tenant not found or a rejected
   access token), the error message suggests checking azure_cloud.

### Azure Setup
 1. Create an app registration in Azure (Microsoft Entra ID) and create a client secret for it. For GCC High and
    DoD tenants, use the Azure Government portal (`https://portal.azure.us`); for China, use
    `https://portal.azure.cn`.
 2. Under **API permissions**, add these Microsoft Graph **Application** permissions and **grant admin consent**:
    * `Mail.Send`, required for every email.
    * `Mail.ReadWrite`, required for emails sent with the draft method (attachments over about 3.5 MB in
      total). Without it, those emails fail with an error that names this permission.
 3. The sender (`from_address` or From (Override)) must be an Exchange Online user or shared mailbox in the
    same tenant.
 4. **Restrict which mailboxes the app can use.** By default these application permissions apply to *every*
    mailbox in the tenant. Use Exchange Online
    [RBAC for Applications](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac)
    (or Application Access Policies) to limit the app to the intended sender mailbox(es).

### Error Handling
Inputs, configuration, and the template are validated before anything is sent, and configuration and input
problems are reported together in one message. The handler fails, with a message naming the template and the
missing item, when:
 * the template, or a snippet it uses, has no active record
 * a date format it uses has no active record, has a Format that is not a strftime pattern, or an
   `${appearance(...)}` tag has no `${format(...)}` part
 * it references submission attachments and no Submission Id was provided
 * the template_attachments_field property names a field that is not on the template form
 * a referenced attachment field does not exist on the submission's form, or is not an attachment field
 * an attachment or inline image cannot be downloaded
 * the attachments are over the size limit

Errors from the Kinetic Platform, Azure AD, and Microsoft Graph are translated into a description of the likely
cause and fix, followed by the raw details for support:
```
Could not send the email: The app is not allowed to send mail as noreply@contoso.com. Make sure the app
registration has the Mail.Send application permission with admin consent granted, ... (Graph:
ErrorAccessDenied - Access is denied. Check credentials and try again.; HTTP 403; request-id: 6a1c...)
```
Include the `request-id` (Graph) or `correlation-id` (Azure AD) when opening a case with Microsoft.

Responses of `429` (throttled) and `503` (unavailable) are retried up to 3 times, waiting for the `Retry-After`
time (capped at 30 seconds). Timeouts and dropped connections while sending are not retried, because the email
may already have been sent. The error message says so; check the sender's Sent Items before running the task
again.

When Error Handling is "Raise Error", the same message is raised instead of returned.

### Notes
 * Exchange Online allows at most 500 recipients (To + CC + BCC) per message.
 * The sender's display name comes from the Exchange mailbox.
 * Debug logging never writes the client secret, access tokens, upload URLs, recipient addresses, or body
   content. It does log template names, attachment file names, and sizes.
 * In Kinetic Task (JRuby), HTTP requests are sent with Java's built-in `HttpURLConnection`, so they use the
   JVM's TLS settings, certificate trust store, and proxy settings (for example the `https.proxyHost` and
   `https.proxyPort` system properties). Outside of JRuby, Ruby's `Net::HTTP` is used.
 * The handler has no bundled gems or libraries. It runs on JRuby 1.7 and later with Java 8 and later.
