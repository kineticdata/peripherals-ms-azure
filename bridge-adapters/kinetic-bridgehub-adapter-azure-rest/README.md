# Kinetic Bridgehub Adapter Azure Rest

This Rest based bridge adapter was designed to work with Remedy Action Reqeust System version 9.
___
## Adapter Configurations
Name | Description
Client Id | The application id assigned by Azure
Client Secret | The secret generated for the app
Tenant Id| The directory tenant the application plans to operate against
Scope | The value passed for the scope parameter in this request should be the resource identifier (application ID URI) of the resource you want, affixed with the .default suffix.
___
## Supported structures
* Users
___
## Example Qualification Mapping
* userId = foo@bar.com
___
## Notes
* To do a retrieve of a user the userId parameter must be passed in the qualification mapping.
* This adapter is hard coded to the make requested against https://graph.microsoft.com/v1.0
* Only sorting supported by the Azure AD source system is allowed. i.e. no adapter side sorting.
* Fields are automatically added to the Azure request as $select=...
    * Fields