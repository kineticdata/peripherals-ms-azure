## Azure Cosmos Document CRUD
Crud operation for interacting with Cosmos DB documents.

### Parameters
Name | Description
----------- | -------------
Error Handling | Determine what to return if an error is encountered.
Method | The Rest method to use when executing handler.  GET PUT POST DELETE
Database Name | The Database name the document is in.
Collection Name | The Collection name the document is in.
Document Name | The Document name/id attempting to create/update.
Partition Key | The Partition key associated with the document.  Used with PUT and POST methods to create or update a record.
Body | This will be the body of the Rest request sent to Cosmos DB.  It can be a SQL style query used for look ups. It can also be used to create or update a document.

### Sample Configuration
Error Handling:      Error Message

### Results
Name | Description
----------- | -------------
Handler Error Message | Error message if an error was encountered and Error Handling is set to "Error Message".
output | Json object that is returned from the request. A GET or POST (with query) will return multiple records that can be access through the Documents property on the return object.  DELETE return an empty object that is set to nil. POST and PUT create and updates will return a single record. 

### Detailed Description
This Handler is only designed to work with Cosmos Documents that are part of a
Collection inside a Database.
Notes:
  * Adding attachments are not supported by the handler.
  * Cosmos does not support upserts.  To do an update of a record it must be retrieved and modified.
  * The handler only support version 2018-12-31 of the Cosmos api, which enforces partition keys on collections.
  * Create, delete and update operations require a Partition Key value.

### Example inputs
Retrieve multiple items from the FamilyDatabase db and FamilyContainer collection.  
`
  'parameters' => {
    'error_handling' => 'Error Message',
    'method' => 'GET',
    'database_name' => 'FamilyDatabase',
    'collection_name' => 'FamilyContainer',
    'document_name' => '',
    'partition_key' => '',
    'body' => '',
  }
`   
Retrieve multiple items from the FamilyDatabase db and FamilyContainer collection base on query. Visit [Getting started with SQL queries](https://docs.microsoft.com/en-us/azure/cosmos-db/sql-query-getting-started) in the cosmos docs for more info.   
`
  'parameters' => {
    'error_handling' => 'Error Message',
    'method' => 'POST',
    'database_name' => 'FamilyDatabase',
    'collection_name' => 'FamilyContainer',
    'document_name' => '',
    'partition_key' => '',
    'body' => '{ "query" : "Select * From root"}',
  }
`  
Create a new item in the FamilyDatabase db and FamilyContainer collection. The collection was set up with Country as the Partition Key.  
`
  'parameters' => {
    'error_handling' => 'Error Message',
    'method' => 'POST',
    'database_name' => 'FamilyDatabase',
    'collection_name' => 'FamilyContainer',
    'document_name' => '',
    'partition_key' => 'USA',
    'body' => '{  
      "id": "Smith.2",  
      "Country": "USA",
      "Parents": [  
        {  
          "FamilyName": null,  
          "FirstName": "Thomas"  
        },  
        {  
          "FamilyName": null,  
          "FirstName": "Mary Kay"  
        }  
      ]
    } ',
  }
`  
Update an item in the FamilyDatabase db and FamilyContainer collection. Updates overwrite the existing object. The items id needs to be provided as the document name. The collection was set up with Country as the Partition Key.  
`
  'parameters' => {
    'error_handling' => 'Error Message',
    'method' => 'PUT',
    'database_name' => 'FamilyDatabase',
    'collection_name' => 'FamilyContainer',
    'document_name' => 'Smith.2',
    'partition_key' => 'USA',
    'body' => '{  
      "id": "Smith.2",  
      "Country": "USA",
      "Parents": [  
        {  
          "FamilyName": "Smith",  
          "FirstName": "Thomas"  
        },  
        {  
          "FamilyName": "Smith",  
          "FirstName": "Mary Kay"  
        }  
      ]
    } ',
  }
`  
Delete an item in the FamilyDatabase db and FamilyContainer collection. The items id needs to be provided as the document name. The collection was set up with Country as the Partition Key.  
`
  'parameters' => {
    'error_handling' => 'Error Message',
    'method' => 'DELETE',
    'database_name' => 'FamilyDatabase',
    'collection_name' => 'FamilyContainer',
    'document_name' => 'Smith.2',
    'partition_key' => 'USA',
    'body' => '',
  }
`  
