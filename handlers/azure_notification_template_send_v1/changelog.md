Azure Notification Template Send V1 (2026-11-04)
 * Attachments are now downloaded directly from the Core API file endpoint
   (/app/api/v1/submissions/{id}/files/{field}/{index}/{name}), which returns the file (or redirects to the
   file store) and accepts the handler's API credentials.  Previously the handler asked .../url for a link and
   downloaded the browser download path (/submissions/...); on installs that do not accept API credentials on
   that path, or route it differently (for example a proxy rule that redirects it to /), the download
   redirected in a loop and failed with "redirected more than 5 times".
 * If the Core API file endpoint returns HTTP 404 (for example on a platform version without that endpoint),
   the handler falls back to the previous .../url download link route.  The debug log records which route
   was used.
 * Readme updated to describe how attachments are downloaded.
 * No changes to inputs, outputs, or info values; the handler version is unchanged.

Azure Notification Template Send V1 (2026-10-28)
 * Attachment and inline image downloads now record each redirect hop: HTTP status, URL without its
   query string, and whether the Kinetic credentials were sent.  Hops are written to the debug log
   (enable_debug_logging), and the redirect chain is included in the error message when a download
   fails after one or more redirects, including the "redirected more than 5 times" error.  This makes
   redirect loops (for example an SSO login redirect, or http/https or host mismatches with api_server)
   visible without reproducing the request by hand.
 * Query strings are removed from logged and reported URLs so presigned storage signatures and SSO
   tokens are not exposed.
 * A redirect to a Location that is not a valid URL now raises a handler error instead of an
   unhandled exception.
 * No changes to inputs, outputs, or info values; the handler version is unchanged.

Azure Notification Template Send V1 (2026-10-01)
 * Initial version.  See README for details.
