package com.kineticdata.bridgehub.adapter.azure.rest;

import com.kineticdata.bridgehub.adapter.BridgeError;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import org.apache.http.Consts;
import org.apache.http.HttpEntity;
import org.apache.http.HttpResponse;
import org.apache.http.NameValuePair;
import org.apache.http.client.entity.UrlEncodedFormEntity;
import org.apache.http.client.methods.HttpGet;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.message.BasicNameValuePair;
import org.apache.http.util.EntityUtils;
import org.json.simple.JSONArray;
import org.json.simple.JSONObject;
import org.json.simple.JSONValue;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * This class is a Rest service helper.
 */
public class AzureRestApiHelper {
    private static final Logger LOGGER = 
        LoggerFactory.getLogger(AzureRestApiHelper.class);
    
    private final String clientId;
    private final String clientSecret;
    private final String tenantId;
    private final String scope;
    private String token;
    
    public AzureRestApiHelper(String tenantId, String clientId,
        String clientSecret, String scope) {
        
    this.clientId = clientId;
    this.clientSecret = clientSecret;
    this.tenantId = tenantId;
    this.scope = scope;
    } 
    
    public JSONObject executeRequest (String url) throws BridgeError{
        return executeRequest (url, 0);
    }
    
    public JSONObject executeRequest (String url, int count) 
        throws BridgeError{
        
        JSONObject output;      
        // System time used to measure the request/response time
        long start = System.currentTimeMillis();
        
        try (
            CloseableHttpClient client = HttpClients.createDefault()
        ) {
            HttpResponse response;
            HttpGet get = new HttpGet(url);
            get.setHeader("Authorization", "Bearer " + token);
            
            response = client.execute(get);
            LOGGER.debug("Recieved response from \"{}\" in {}ms.",
                url,
                System.currentTimeMillis()-start);

            int responseCode = response.getStatusLine().getStatusCode();
            LOGGER.trace("Request response code: " + responseCode);
            
            HttpEntity entity = response.getEntity();
            
            // Confirm that response is a JSON object
            output = parseResponse(EntityUtils.toString(entity));
            
            if (response.getStatusLine().getStatusCode() == 404) {
                throw new BridgeError("404: Page not found");
            } else if (response.getStatusLine().getStatusCode() == 400) {
                throw new BridgeError("400: Bad Reqeust");
            } else if (response.getStatusLine().getStatusCode() == 500) {
                throw new BridgeError("500 Internal Server Error");
            } else if(responseCode == 401){
                // If token has expired get fresh token
                getToken();
                // If count is greater than 2 assume stop token retry attempts.
                if (count < 2) {
                    output = executeRequest(url, count + 1);
                } else {
                    throw new BridgeError(count + " attempts were made to get a"
                        + "new token without success.");
                }
            }
        }
        catch (IOException e) {
            throw new BridgeError(
                "Unable to make a connection to the Azure service server.", e);
        }
        
        return output;
    }
    
    // Get a JWT to be used with subsequent requests.
    public void getToken () throws BridgeError {
        String url = "https://login.microsoftonline.com/" + tenantId
            + "/oauth2/v2.0/token"; 
        
        try (
            CloseableHttpClient client = HttpClients.createDefault()
        ) {
            HttpResponse response;
            HttpPost httpPost = new HttpPost(url);

            // Create entity with username and pass for use in the Post.
            List<NameValuePair> form = new ArrayList<>();
            form.add(new BasicNameValuePair("client_id", clientId));
            form.add(new BasicNameValuePair("client_secret", clientSecret));
            form.add(new BasicNameValuePair("grant_type", "client_credentials"));
            form.add(new BasicNameValuePair("scope", scope));
            UrlEncodedFormEntity requestEntity = new UrlEncodedFormEntity(form, Consts.UTF_8);

            httpPost.setEntity(requestEntity);
            httpPost.setHeader("Content-Type", "application/x-www-form-urlencoded");

            // Make the call to the REST source to retrieve data and convert the 
            // response from an HttpEntity object into a Java string so more response
            // parsing can be done.
            response = client.execute(httpPost);
            HttpEntity entity = response.getEntity();
            JSONObject jsonResponse = parseResponse(EntityUtils.toString(entity));

            token = jsonResponse.get("access_token").toString();
            LOGGER.debug("Successfully retreived token. It will expire in " +
                jsonResponse.get("expires_in") + " seconds");
            
        } catch (IOException e) {
            throw new BridgeError("Unable to make a connection to the REST"
                + " Service", e);
        }
    }
    
        
    private JSONObject parseResponse(String output) throws BridgeError{
                
        JSONObject jsonResponse = new JSONObject();
        try {
            // Parse the response string into a JSONObject
            jsonResponse = (JSONObject)JSONValue.parse(output);
        } catch (ClassCastException e){
            JSONArray error = (JSONArray)JSONValue.parse(output);
            throw new BridgeError("Error caught in retrieve: "
                + ((JSONObject)error.get(0)).get("messageText"));
        } catch (Exception e) {
            throw new BridgeError("An unexpected error has occured " + e);
        }
        
        if(jsonResponse.get("error") != null) {
            JSONObject error = (JSONObject)jsonResponse.get("error");
            throw new BridgeError("Received error: " 
                + error.get("code").toString() + ", Description: "
                + error.get("message").toString());
        }
        
        return jsonResponse;
    }
}
