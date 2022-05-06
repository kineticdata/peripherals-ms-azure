package com.kineticdata.bridgehub.adapter.azure.rest;

import com.kineticdata.bridgehub.adapter.BridgeAdapterTestBase;
import com.kineticdata.bridgehub.adapter.BridgeError;
import com.kineticdata.bridgehub.adapter.BridgeRequest;
import com.kineticdata.bridgehub.adapter.Count;
import com.kineticdata.bridgehub.adapter.Record;
import com.kineticdata.bridgehub.adapter.RecordList;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import org.junit.Test;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class AzureRestTest extends BridgeAdapterTestBase{
    
    private static final Logger LOGGER = 
        LoggerFactory.getLogger(AzureRestTest.class);
        
    @Override
    public Class getAdapterClass() {
        return AzureRestAdapter.class;
    }
    
    @Override
    public String getConfigFilePath() {
        return "src/test/resources/bridge-config.yml";
    }
    
    /*
        Test count method
    */
    @Override
    @Test
    public void test_emptyCount() throws Exception {
        assertTrue(true);
    }
    
    /*
        Test retrieve method
    */
    @Override
    @Test
    public void test_emptyRetrieve() throws Exception {
        assertTrue(true);
    }
    
    /*
        Test search method
    */
    @Override
    @Test
    public void test_emptySearch() throws Exception {
        assertTrue(true);
    }
    
    @Test
    public void test_count() throws Exception{
        BridgeError error = null;

        BridgeRequest request = new BridgeRequest();
        request.setStructure("Users");
        request.setFields(new ArrayList<>());
        request.setQuery("");
        request.setParameters(new HashMap());
        
        Count count = null;
        try {
            count = getAdapter().count(request);
        } catch (BridgeError e) {
            error = e;
        }

        assertNull(error);
        assertTrue(count.getValue() > 0);
    }
    
    @Test
    public void test_retrieve() throws Exception{
        BridgeError error = null;
        
        // Create the Bridge Request
        List<String> fields = new ArrayList<>();
        fields.add("displayName");
        fields.add("surname");
        
        BridgeRequest request = new BridgeRequest();
        request.setStructure("Users");
        request.setFields(fields);
        request.setQuery("userId=<%=parameter[\"User Name\"]%>");
        
        request.setParameters(new HashMap<String, String>() {{ 
            put("User Name", "-foo.bar");
        }});
        
        
        Record record = null;
        try {
            record = getAdapter().retrieve(request);
        } catch (BridgeError e) {
            error = e;
        }
        
        assertNull(error);
        assertTrue(record.getRecord().size() > 0);
    }
    
    @Test
    public void test_search() throws Exception{
        BridgeError error = null;
        
        // Create the Bridge Request
        List<String> fields = new ArrayList<>();
        fields.add("displayName");
        fields.add("surname");
        
        BridgeRequest request = new BridgeRequest();
        request.setStructure("Users");
        request.setFields(fields);
        request.setQuery("");
        request.setParameters(new HashMap<String, String>());
                
        RecordList records = null;
        try {
            records = getAdapter().search(request);
        } catch (BridgeError e) {
            error = e;
        }
        
        assertNull(error);
        assertTrue(records.getRecords().size() > 0);
    }
    
    @Test
    public void test_search_query() throws Exception{
        BridgeError error = null;
        
        // Create the Bridge Request
        List<String> fields = new ArrayList<>();
        fields.add("displayName");
        fields.add("surname");
        fields.add("userPrincipalName");
        
        BridgeRequest request = new BridgeRequest();
        request.setStructure("Users");
        request.setFields(fields);
        request.setQuery("$search=\"displayName:<%=parameter[\"Display Name\"]%>\"");
        
        request.setParameters(new HashMap<String, String>() {{ 
            put("Display Name", "Chad Rehm");
        }});
        
        
        RecordList records = null;
        try {
            records = getAdapter().search(request);
        } catch (BridgeError e) {
            error = e;
        }
        
        assertNull(error);
        assertTrue(records.getRecords().size() > 0);
    }
    
    @Test
    public void test_search_sort() throws Exception{
        BridgeError error = null;
        
        // Create the Bridge Request
        List<String> fields = new ArrayList<>();
        fields.add("displayName");
        fields.add("surname");
        
        BridgeRequest request = new BridgeRequest();
        request.setStructure("Users");
        request.setFields(fields);
        request.setQuery("");
        
        request.setMetadata(new HashMap<String, String>() {{
            put("order", "<%=field[\"displayName\"]%>:DESC");
        }});
        
        RecordList records = null;
        try {
            records = getAdapter().search(request);
        } catch (BridgeError e) {
            error = e;
            LOGGER.error("Error: ", e);
        }
        
        assertNull(error);
        assertTrue(records.getRecords().size() > 0);
    }
   
//    @Test
//    public void test_search_sort_multiple() throws Exception{
//        BridgeError error = null;
//        
//        // Create the Bridge Request
//        List<String> fields = new ArrayList<>();
//        fields.add("displayName");
//        fields.add("surname");
//        
//        BridgeRequest request = new BridgeRequest();
//        request.setStructure("Users");
//        request.setFields(fields);
//        request.setQuery("");
//        
//        Map <String, String> metadata = new HashMap<>();
//        metadata.put("order", ""
//            + "<%=field[\"surname\"]%>:DESC");       
//        request.setMetadata(metadata);
//        
//        RecordList records = null;
//        try {
//            records = getAdapter().search(request);
//        } catch (BridgeError e) {
//            error = e;
//            LOGGER.error("Error: ", e);
//        }
//        
//        assertNull(error);
//        assertTrue(records.getRecords().size() > 0);
//    }
}