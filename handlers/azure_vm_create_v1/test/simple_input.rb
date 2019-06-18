{
  'info' => {
    'server' => 'https://management.core.windows.net'
  },
  'parameters' => {
    'subscription_id' => 'abc123-xyz-456',
    'vm_name' => 'Test VM',
    'vm_user' => 'Test',
    'password' => 'Password123',
    'os_type' => 'Windows',
    'image' => 'CentOS-7-GenericCloud-20160608',
    'location' => 'Central US',
    'cloud_service_name' => 'Test Cloud Service',
    'vm_size' => 'Standard_D1_v2',
    'affinity_group_name' => 'affinity1',
    'virtual_network_name' => 'test_virtual_network',
    'subnet_name' => 'test_subnet',
    'availability_set_name' => 'availabiltyset1',
    'endpoints' => '<InputEndpoint>
                      <LocalPort>998</LocalPort>
                      <Name>test-1</Name>
                      <Port>996</Port>
                      <Protocol>TCP</Protocol>
                    </InputEndpoint>'
  }
}