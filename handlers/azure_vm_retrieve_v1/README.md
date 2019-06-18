## Azure VM Retrieve
This retrieves information of an existing Azure Virtual Machine.

### Parameters
[Subscription ID]
  The Azure Subscription ID.
[VM Name]
  The Name of the Virtual Machine to be retrieved.
[Cloud Service Name]
  Cloud Service the virtual machine belongs in.

### Results
[Output]
  JSON of the Virtual Machine information.

#### Sample Configuration
Subscription ID:      55c212bdee118e0662030003
VM Name:              kdtestmachine2
Cloud Service Name:   Test

### Detailed Description
This handler uses the Azure Service Management API library to retrieve a Virtual Machine associated to the security certificate tied to the handler.