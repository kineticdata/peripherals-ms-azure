{
  'info' => {
    'enable_debug_logging'=>'yes',
    'origin' => '',
    'master_key' => '',
  },
  # 'parameters' => {
  #   'error_handling' => 'Error Message',
  #   'method' => 'GET',
  #   'database_name' => 'FamilyDatabase',
  #   'collection_name' => 'FamilyContainer',
  #   'document_name' => '',
  #   'partition_key' => '',
  #   'body' => '',
  # }
  # 'parameters' => {
  #   'error_handling' => 'Error Message',
  #   'method' => 'POST',
  #   'database_name' => 'FamilyDatabase',
  #   'collection_name' => 'FamilyContainer',
  #   'document_name' => '',
  #   'partition_key' => '',
  #   'body' => '{ "query" : "Select * From root"}',
  # }
  # 'parameters' => {
  #   'error_handling' => 'Error Message',
  #   'method' => 'POST',
  #   'database_name' => 'FamilyDatabase',
  #   'collection_name' => 'FamilyContainer',
  #   'document_name' => '',
  #   'partition_key' => 'USA',
  #   'body' => '{  
  #     "id": "Smith.2",  
  #     "Country": "USA",
  #     "Parents": [  
  #       {  
  #         "FamilyName": null,  
  #         "FirstName": "Thomas"  
  #       },  
  #       {  
  #         "FamilyName": null,  
  #         "FirstName": "Mary Kay"  
  #       }  
  #     ]
  #   } ',
  # }
  # 'parameters' => {
  #   'error_handling' => 'Error Message',
  #   'method' => 'PUT',
  #   'database_name' => 'FamilyDatabase',
  #   'collection_name' => 'FamilyContainer',
  #   'document_name' => 'Smith.2',
  #   'partition_key' => 'USA',
  #   'body' => '{  
  #     "id": "Smith.2",  
  #     "Country": "USA",
  #     "Parents": [  
  #       {  
  #         "FamilyName": "Smith",  
  #         "FirstName": "Thomas"  
  #       },  
  #       {  
  #         "FamilyName": "Smith",  
  #         "FirstName": "Mary Kay"  
  #       }  
  #     ]
  #   } ',
  # }
  'parameters' => {
    'error_handling' => 'Error Message',
    'method' => 'DELETE',
    'database_name' => 'FamilyDatabase',
    'collection_name' => 'FamilyContainer',
    'document_name' => 'Smith.2',
    'partition_key' => 'USA',
    'body' => '',
  }
}

