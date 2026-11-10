{
  'info' => {
    'tenant_id' => "00000000-0000-0000-0000-000000000000",
    'client_id' => "00000000-0000-0000-0000-000000000000",
    'client_secret' => "not-used",
    'azure_cloud' => 'Global',
    'from_address' => "noreply@example.com",
    'enable_debug_logging' => 'true'
  },
  'parameters' => {
    'error_handling' => 'Error Message',
    'from_override' => '',
    'to' => 'jane.doe@example, bob@',
    'cc' => 'x@@example.com',
    'bcc' => '',
    'subject' => 'Validation test',
    'html_body' => '',
    'text_body' => 'Fails validation before any network call is made.'
  }
}
