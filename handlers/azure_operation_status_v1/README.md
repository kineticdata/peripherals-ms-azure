## Azure Operation Status
This handler checks to see the status of an operation given the request id.

### Parameters
[Subscription ID]
  The Azure Subscription ID.
[Request ID]
  The Request ID of an operation.

### Results
[Status]
  Status of the operation (Succeeded, Failed, In Progress).

#### Sample Configuration
Subscription ID:      55c212bdee118e0662030003
Request ID:           abc12345xyz

### Detailed Description
This handler uses the Azure Service Management API library to retrieve the status
of an operation.