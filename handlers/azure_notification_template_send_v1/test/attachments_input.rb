{
  'info' => {
    'tenant_id' => '',
    'client_id' => '',
    'client_secret' => '',
    'from_address' => '',
    'api_server' => 'https://my-space.kinops.io',
    'api_username' => '',
    'api_password' => '',
    'space_slug' => '',
    'kapp_slug' => 'datastore',
    'form_slug_data' => 'notification-data',
    'form_slug_dates' => 'notification-template-dates',
    'template_attachments_field' => 'Email Template Attachments',
    'max_attachment_size_mb' => '25',
    'enable_debug_logging' => 'true'
  },
  'parameters' => {
    'error_handling' => 'Error Message',
    'space_slug' => '',
    'recipient_json' => '{"type":"user","smtpaddress":{"to":"jane.doe@example.com"},"language":"","region":"","email notifications":"yes"}',
    'notification_template_name' => 'Service Submitted With Attachments',
    'replacement_values' => '{"values":{"Summary":"New monitor"},"submission":{"submittedAt":"2026-10-01T15:30:00.000Z","handle":"ABC123"},"user":{"displayName":"Jane Doe"}}',
    'submission_id' => '<submission id with files in an attachment field>',
    'from_override' => ''
  }
}
