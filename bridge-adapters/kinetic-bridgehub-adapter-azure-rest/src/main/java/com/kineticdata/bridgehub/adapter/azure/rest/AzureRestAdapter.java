package com.kineticdata.bridgehub.adapter.azure.rest;

import com.kineticdata.bridgehub.adapter.BridgeAdapter;
import com.kineticdata.bridgehub.adapter.BridgeError;
import com.kineticdata.bridgehub.adapter.BridgeRequest;
import com.kineticdata.bridgehub.adapter.BridgeUtils;
import com.kineticdata.bridgehub.adapter.Count;
import com.kineticdata.bridgehub.adapter.Record;
import com.kineticdata.bridgehub.adapter.RecordList;
import com.kineticdata.commons.v1.config.ConfigurableProperty;
import com.kineticdata.commons.v1.config.ConfigurablePropertyMap;
import java.io.IOException;
import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.apache.http.NameValuePair;
import org.apache.http.client.utils.URLEncodedUtils;
import org.apache.http.message.BasicNameValuePair;
import org.json.simple.JSONArray;
import org.json.simple.JSONObject;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class AzureRestAdapter implements BridgeAdapter {
    /*----------------------------------------------------------------------------------------------
     * CONSTRUCTOR
     *--------------------------------------------------------------------------------------------*/
    public AzureRestAdapter () {
        // Parse the query and exchange out any parameters with their parameter 
        // values. ie. change the query username=<%=parameter["Username"]%> to
        // username=test.user where parameter["Username"]=test.user
        this.parser = new AzureRestQualificationParser();
    }
    
    /*----------------------------------------------------------------------------------------------
     * STRUCTURES
     *      AgentAdapterMapping( Structure Name, Path Function)
     *--------------------------------------------------------------------------------------------*/
    public static Map<String,AgentAdapterMapping> MAPPINGS 
        = new HashMap<String,AgentAdapterMapping>() {{
        put("Users", new AgentAdapterMapping("Users", 
            AzureRestAdapter::pathUsers));
    }};
    
    /*----------------------------------------------------------------------------------------------
     * PROPERTIES
     *--------------------------------------------------------------------------------------------*/

    /** Defines the adapter display name */
    public static final String NAME = "Azure Rest Bridge";

    /** Defines the LOGGER */
    protected static final Logger LOGGER = LoggerFactory.getLogger(AzureRestAdapter.class);
    
    /** Adapter version constant. */
    public static String VERSION = "";
    /** Load the properties version from the version.properties file. */
    static {
        try {
            java.util.Properties properties = new java.util.Properties();
            properties.load(AzureRestAdapter.class.getResourceAsStream("/"+AzureRestAdapter.class.getName()+".version"));
            VERSION = properties.getProperty("version");
        } catch (IOException e) {
            LOGGER.warn("Unable to load "+AzureRestAdapter.class.getName()+" version properties.", e);
            VERSION = "Unknown";
        }
    }

    /** Defines the collection of property names for the adapter */
    public static class Properties {
        public static final String PROPERTY_CLIENT_ID = "Client Id";
        public static final String PROPERTY_CLIENT_SECRET = "Client Secret";
        public static final String PROPERTY_TENANT_ID = "Tenant Id";
        public static final String PROPERTY_SCOPE = "Scope";

    }

    private final ConfigurablePropertyMap properties = new ConfigurablePropertyMap(
        new ConfigurableProperty(Properties.PROPERTY_CLIENT_ID).setIsRequired(true),
        new ConfigurableProperty(Properties.PROPERTY_CLIENT_SECRET)
            .setIsRequired(true).setIsSensitive(true),
        new ConfigurableProperty(Properties.PROPERTY_TENANT_ID).setIsRequired(true),
        new ConfigurableProperty(Properties.PROPERTY_SCOPE).setIsRequired(true)
    );

    // Local variables to store the property values in
    private AzureRestQualificationParser parser;
    private AzureRestApiHelper azureApiHelper;
    
    // Constants
    private static final String API_LOCATION = "https://graph.microsoft.com/v1.0";

    /*---------------------------------------------------------------------------------------------
     * SETUP METHODS
     *-------------------------------------------------------------------------------------------*/

    @Override
    public void initialize() throws BridgeError {
        // Initializing the variables with the property values that were passed
        // when creating the bridge so that they are easier to use
        String clientId = properties.getValue(Properties.PROPERTY_CLIENT_ID);
        String clientSecret = properties.getValue(Properties.PROPERTY_CLIENT_SECRET);
        String tenantId = properties.getValue(Properties.PROPERTY_TENANT_ID);
        String scope = properties.getValue(Properties.PROPERTY_SCOPE);
        
        azureApiHelper = new AzureRestApiHelper(tenantId, clientId, clientSecret,
            scope);
        parser = new AzureRestQualificationParser();
        
        azureApiHelper.getToken();
    }

    @Override
    public String getName() {
        return NAME;
    }

    @Override
    public String getVersion() {
       return VERSION;
    }

    @Override
    public void setProperties(Map<String,String> parameters) {
        // This should always be the same unless there are special circumstances
        // for changing it
        properties.setValues(parameters);
    }

    @Override
    public ConfigurablePropertyMap getProperties() {
        // This should always be the same unless there are special circumstances
        // for changing it
        return properties;
    }

    /*---------------------------------------------------------------------------------------------
     * IMPLEMENTATION METHODS
     *-------------------------------------------------------------------------------------------*/

    @Override
    public Count count(BridgeRequest request) throws BridgeError {
        request.setQuery(
            parser.parse(request.getQuery(),request.getParameters()));
        
        // Log the access
        LOGGER.trace("Counting records");
        LOGGER.trace("  Structure: " + request.getStructure());
        LOGGER.trace("  Query: " + request.getQuery());

        // parse Structure
        String[] structureArray = request.getStructure().trim().split("\\s*>\\s*");
        // get Structure model
        AgentAdapterMapping mapping = getMapping(structureArray[0]);

        Map<String, String> parameters = parser.getParameters(request.getQuery());
        
                // Path builder functions may mutate the parameters Map;
        String path = mapping.getPathbuilder().apply(null, parameters);
        
        Map<String, NameValuePair> parameterMap = buildNameValuePairMap(parameters);
        
        // Retrieve the objects based on the structure from the source
        JSONObject object = azureApiHelper.executeRequest(getUrl(path, 
            parameterMap));
        
        Integer count;
        // "value" == multiple and no value == single.  Error objects are caught 
        // in RestApiHelper.
        if (object.containsKey("value")) {
            // Get domain specific data.
            JSONArray entries = (JSONArray)object.get("value");
            count = entries.size();
        } else {
            count = 1;
        }
        
        return new Count(count);
    }

    @Override
    public Record retrieve(BridgeRequest request) throws BridgeError {
        request.setQuery(
            parser.parse(request.getQuery(),request.getParameters()));
        
        // Log the access
        LOGGER.trace("Retrieving Kinetic Request CE Record");
        LOGGER.trace("  Structure: " + request.getStructure());
        LOGGER.trace("  Query: " + request.getQuery());
        LOGGER.trace("  Fields: " + request.getFieldString());
        
        // parse Structure
        String[] structureArray = request.getStructure().trim().split("\\s*>\\s*");
        // get Structure model
        AgentAdapterMapping mapping = getMapping(structureArray[0]);
        
        Map<String, String> parameters = parser.getParameters(request.getQuery());
        
        List<String> fields = request.getFields();
        if (fields == null) {
            fields = new ArrayList();
        } else {
            // Only get a list of the requested fields from the Azure API.
            parameters.put("$select", String.join(",",fields));
        }
        
        // Path builder functions may mutate the parameters Map;
        String path = mapping.getPathbuilder().apply(null, parameters);
        
        Map<String, NameValuePair> parameterMap = buildNameValuePairMap(parameters);
        
        // Retrieve the objects based on the structure from the source
        JSONObject object = azureApiHelper.executeRequest(getUrl(path, 
            parameterMap));

        // Get domain specific data. A single reture will come as an object.
        // Multiple results come back in the "value" array.
        JSONArray obj = (JSONArray)(object).get("value");
        Record record = new Record();
        if (obj == null || obj.size() == 1) {
            if (obj != null) {
                // Reassign object to single result 
                object = (JSONObject)obj.get(0);
            }
            // Set object to user defined fields
            Set<Object> removeKeySet = buildKeySet(fields, object);
            object.keySet().removeAll(removeKeySet);

            // Create a Record object from the responce JSONObject
            record = new Record(object);
        } else if (obj.size() == 0) {
            LOGGER.debug("No results found for query: {}", request.getQuery());
        } else {
            throw new BridgeError ("Retrieve must return a single result."
                + " Multiple results found.");
        }
        
        return record;
    }

    @Override
    public RecordList search(BridgeRequest request) throws BridgeError {
        request.setQuery(
            parser.parse(request.getQuery(),request.getParameters()));
        
        // Log the access
        LOGGER.trace("Searching Records");
        LOGGER.trace("  Structure: " + request.getStructure());
        LOGGER.trace("  Query: " + request.getQuery());
        LOGGER.trace("  Fields: " + request.getFieldString());

        // parse Structure
        String[] structureArray = request.getStructure().trim().split("\\s*>\\s*");
        // get Structure model
        AgentAdapterMapping mapping = getMapping(structureArray[0]);

        Map<String, String> parameters = parser.getParameters(request.getQuery());
        Map<String, String> metadata = request.getMetadata() != null ?
                request.getMetadata() : new HashMap<>();

        List<String> fields = request.getFields();
        if (fields == null) {
            fields = new ArrayList();
        } else {
            LOGGER.trace("Adding feilds \"{}\" to request parameters as $select",
                String.join(",",fields));
            // Only get a list of the requested fields from the Azure API.
            parameters.put("$select", String.join(",",fields));
        }
        
        // If form defines sort order use it. This will overwrite $orderby in the
        // qualification mapping.
        if (metadata.get("order") != null) {
            parameters.put("$orderby", addSort(metadata.get("order")));
        }

        // clear metadata object to be repopulated for response.
        metadata.clear();

        // Path builder functions may mutate the parameters Map;
        String path = mapping.getPathbuilder().apply(null, parameters);
        
        // If a limit was not provided get the top 999.
        if (!parameters.containsKey("$top")) {
            parameters.put("$top", "999");
        }
        Map<String, NameValuePair> parameterMap = buildNameValuePairMap(parameters);
        
        // Retrieve the objects based on the structure from the source
        JSONObject object = azureApiHelper.executeRequest(getUrl(path, 
            parameterMap));
        
        // If not all the result were returned then a "skiptoken" is provided
        if (object.containsKey("$skiptoken")) {
            metadata.put("$skiptoken", (String)object.get("$skiptoken"));
        }

        // Get domain specific data.
        JSONArray entries = (JSONArray)object.get("value");

        // Create a List of records that will be used to make a RecordList object
        List<Record> recordList = new ArrayList<>();
        
        if(entries != null && entries.isEmpty() != true){
            JSONObject firstObject = (JSONObject)entries.get(0);

            // Set object to user defined fields
            Set<Object> removeKeySet = buildKeySet(fields, firstObject);

            // Iterate through the responce objects and make a new Record for each.
            for (Object o : entries) {
                JSONObject entry = (JSONObject)o;

                entry.keySet().removeAll(removeKeySet);
        
                Record record;
                if (object != null) {
                    record = new Record(entry);
                } else {
                    record = new Record();
                }
                // Add the created record to the list of records
                recordList.add(record);
            }
        }
        
        return new RecordList(fields, recordList, metadata);
    }

    /*----------------------------------------------------------------------------------------------
     * HELPER METHODS
     *--------------------------------------------------------------------------------------------*/
    /**
     * This method checks that the structure on the request matches on in the 
     * Mapping internal class.  Mappings map directly to the adapters supported 
     * Structures.  
     * 
     * @param structure
     * @return Mapping
     * @throws BridgeError 
     */
    protected AgentAdapterMapping getMapping (String structure) throws BridgeError{
        AgentAdapterMapping mapping = MAPPINGS.get(structure);
        if (mapping == null) {
            throw new BridgeError("Invalid Structure: '" 
                + structure + "' is not a valid structure");
        }
        return mapping;
    }
    
    /**
     * Convert parameters from a String to a NameValuePair for use with building
     * the URL parameters
     * 
     * @param parameters
     * @return Map<String, NameValuePair>
     */
    protected Map<String, NameValuePair> buildNameValuePairMap(
        Map<String, String> parameters) {
        
        Map<String, NameValuePair> parameterMap = new HashMap<>();

        parameters.forEach((key, value) -> {
            parameterMap.put(key, new BasicNameValuePair(key, value));
        });
        
        return parameterMap;
    }
    
    /**
     * Build URL to be used when making request to the source system.
     * 
     * @param path
     * @param parameters
     * @return String
     */
    protected String getUrl(String path, Map<String, NameValuePair> parameters) {
        
        return String.format("%s?%s", path, 
            URLEncodedUtils.format(parameters.values(), Charset.forName("UTF-8")));
    }
 
    /**
     * Take the sort order from metadata and add it to parameters for use with
     * request.
     * 
     * @param order
     * @return
     * @throws BridgeError 
     */
    protected String addSort(String order) throws BridgeError {
        
        LinkedHashMap<String,String> sortOrderItems = getSortOrderItems(
                BridgeUtils.parseOrder(order));
        String sortOrderString = sortOrderItems.entrySet().stream().map(entry -> {
            return entry.getKey() + " " + entry.getValue().toLowerCase();
        }).collect(Collectors.joining(","));
                    
        LOGGER.trace("Adding $orderby parameter because form has order "
            + "feilds \"{}\" defined", sortOrderString);
        return sortOrderString;
    }
    
    /**
     * Create a set of keys to remove from object prior to creating Record.
     * 
     * @param fields
     * @param obj
     * @return 
     */
    protected Set<Object> buildKeySet(List<String> fields, JSONObject obj) {
        if(fields.isEmpty()){
            fields.addAll(obj.keySet());
        }
            
        // If specific fields were specified then we remove all of the 
        // nonspecified properties from the object.
        Set<Object> removeKeySet = new HashSet<>();
        for(Object key: obj.keySet()){
            if(!fields.contains(key)){
                LOGGER.trace("Remove Key: "+key);
                removeKeySet.add(key);
            }
        }
        return removeKeySet;
    }
    
    /**
     * Ensure that the sort order list is linked so that order can not be changed.
     * 
     * @param uncastSortOrderItems
     * @return
     * @throws IllegalArgumentException 
     */
    private LinkedHashMap<String, String> 
        getSortOrderItems (Map<String, String> uncastSortOrderItems)
        throws IllegalArgumentException{
        
        /* results of parseOrder does not allow for a structure that 
         * guarantees order.  Casting is required to preserver order.
         */
        if (!(uncastSortOrderItems instanceof LinkedHashMap)) {
            throw new IllegalArgumentException("Sort Order Items was invalid.");
        }
        
        return (LinkedHashMap)uncastSortOrderItems;
    }
    
    /**
     * Used to build the path for the Users structure.  If provided a parameter
     * of "userId" will do a retrieve.
     * 
     * @param _noOp
     * @param parameters
     * @return 
     */
    protected static String pathUsers(String [] _noOp,
        Map<String, String> parameters) {
        
        String path;
        if (parameters != null && parameters.containsKey("userId")){
            path = String.format("%s/users/%s", API_LOCATION,
                parameters.get("userId"));
            parameters.remove("userId");
        } else {
            path = API_LOCATION + "/users";
        }

        return path;
    }
}
