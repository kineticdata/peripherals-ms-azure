package com.kineticdata.bridgehub.adapter.azure.rest;

import org.apache.http.client.methods.HttpGet;
import org.junit.Test;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.assertFalse;

public class AzureRestApiHelperTest {
    @Test
    public void test_includes_search() {
        HttpGet get = new HttpGet("https://graph.microsoft.com/v1.0/users?" +
            "%24top=999&%24select=displayName%2Csurname&%24search=%22foo:bar%22");
        
        AzureRestApiHelper helper = new AzureRestApiHelper("", "", "", "");
        
        assertTrue(helper.isAdvancedQuery(get));
    }
    
    @Test
    public void test_includes_no_search() {
        HttpGet get = new HttpGet("https://graph.microsoft.com/v1.0/users?" +
            "%24top=999&%24select=displayName%2Csurname&%24");
        
        AzureRestApiHelper helper = new AzureRestApiHelper("", "", "", "");
        
        assertFalse(helper.isAdvancedQuery(get));
    }
    
    @Test
    public void test_includes_count_param() {
        HttpGet get = new HttpGet("https://graph.microsoft.com/v1.0/users?" +
            "%24top=999&%24select=displayName%2Csurname&%24count=true");
        
        AzureRestApiHelper helper = new AzureRestApiHelper("", "", "", "");
        
        assertTrue(helper.isAdvancedQuery(get));
    }
    
    @Test
    public void test_includes_count() {
        HttpGet get = new HttpGet("https://graph.microsoft.com/v1.0/%24count");
        
        AzureRestApiHelper helper = new AzureRestApiHelper("", "", "", "");
        
        assertTrue(helper.isAdvancedQuery(get));
    }
    
    @Test
    public void test_includes_no_count() {
        HttpGet get = new HttpGet("https://graph.microsoft.com/v1.0/users?" +
            "%24top=999&%24select=displayName%2Csurname&%24");
        
        AzureRestApiHelper helper = new AzureRestApiHelper("", "", "", "");
        
        assertFalse(helper.isAdvancedQuery(get));
    }
}
