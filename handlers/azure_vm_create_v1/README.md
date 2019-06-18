## Azure VM Create
This handler creates a virtual machine in Azure.

### Parameters
[subscription_id]
  The Azure Subscription ID.
[vm_name]
  The Name of the Virtual Machine to be started.
[vm_user]
  The new user assigned to the virtual machine being created.
[password]
  The password for the new users.
[image]
  Image being used to create the VM.
[location]
  Location of the VM (ex: USGov Iowa).
[cloud_service_name]
  Name of the cloud service.
[vm_size]
  Size of the VM being created.
[affinity_group_name]
  Affinity group name.
[virtual_network_name]
  Virtual network name.
[subnet_name]
  Subnet name.
[availability_set_name]
  Availability set name.
[endpoints]
  Endpoints **Must be in XML format.** 

### Results
The ID of the request is returned.

#### Sample Configuration
subscription_id:			  55c212bdee118e0662030003
vm_name:                kdtestmachine2
vm_user:                kineticdata
password:               Password123
image:                  CentOS-7-GenericCloud-20160608
location:               USGov Iowa
cloud_service_name:     kinetictest
vm_size:                Standard_D1_v2
affinity_group_name:    affinity1
virtual_network_name:   nitc_test
subnet_name:            test_net1
availability_set_name:  availabiltyset1
endpoints:              <InputEndpoint>
                          <LocalPort>998</LocalPort>
                          <Name>test-1</Name>
                          <Port>996</Port>
                          <Protocol>TCP</Protocol>
                        </InputEndpoint>

### Detailed Description
This handler uses the Azure Service Management API to create a new Virtual Machine.

# Endpoints
Endpoints must be in XML format. To see valid XML structure, visit https://msdn.microsoft.com/en-us/library/azure/jj157194.aspx

# Notes
For information on how to create a self-signed certificate, visit the Ruby SDK page at https://github.com/Azure/azure-sdk-for-ruby