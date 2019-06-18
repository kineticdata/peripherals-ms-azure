## Azure Cloud Service Create
This handler creates a new cloud service in Azure.

### Parameters
[subscription_id]
  The Azure Subscription ID.
[location]
  Location of the VM (ex: USGov Iowa).
[cloud_service_name]
  Name of the cloud service.

### Results
This handler returns the cloud service name.

#### Sample Configuration
subscription_id:			  55c212bdee118e0662030003
location:               East US
cloud_service_name:     kinetictest

### Detailed Description
This handler uses the Azure Service Management API to create a new Cloud Service.

# Notes
For information on how to create a self-signed certificate, visit the Ruby SDK page at https://github.com/Azure/azure-sdk-for-ruby