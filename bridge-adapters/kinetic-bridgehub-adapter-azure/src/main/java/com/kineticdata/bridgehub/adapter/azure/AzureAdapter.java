package com.kineticdata.bridgehub.adapter.azure;

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
import java.security.KeyManagementException;
import java.security.KeyStoreException;
import java.security.NoSuchAlgorithmException;
import java.util.Map;
import javax.net.ssl.SSLContext;
import java.io.BufferedReader;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.MalformedURLException;
import java.net.URL;
import java.security.KeyStore;
import java.security.SecureRandom;
import java.security.UnrecoverableKeyException;
import java.security.cert.CertificateException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLSocketFactory;
import org.json.JSONArray;
import org.json.JSONObject;
import org.json.XML;

public class AzureAdapter implements BridgeAdapter {
    /*----------------------------------------------------------------------------------------------
     * PROPERTIES
     *--------------------------------------------------------------------------------------------*/
    
    /** Defines the adapter display name */
    public static final String NAME = "Azure Bridge";

    /** Adapter version constant. */
    public static String VERSION;
    /** Load the properties version from the version.properties file. */
    static {
        try {
            java.util.Properties properties = new java.util.Properties();
            properties.load(AzureAdapter.class.getResourceAsStream("/"+AzureAdapter.class.getName()+".version"));
            VERSION = properties.getProperty("version");
        } catch (IOException e) {
            VERSION = "Unknown";
        }
    }
    
    /** Defines the collection of property names for the adapter */
    public static class Properties {
        public static final String KEYSTORE_PATH = "Keystore Path";
        public static final String KEYSTORE_PASSWORD = "Keystore Password";
    }
    
    private final ConfigurablePropertyMap properties = new ConfigurablePropertyMap(
        new ConfigurableProperty(Properties.KEYSTORE_PATH).setIsRequired(true),
        new ConfigurableProperty(Properties.KEYSTORE_PASSWORD).setIsRequired(true).setIsSensitive(true)
    );
    
    private String keystorePath;
    private String keystorePassword;
    
    /*---------------------------------------------------------------------------------------------
     * SETUP METHODS
     *-------------------------------------------------------------------------------------------*/

    @Override
    public void initialize() throws BridgeError {
        this.keystorePath = properties.getValue(Properties.KEYSTORE_PATH);
        this.keystorePassword = properties.getValue(Properties.KEYSTORE_PASSWORD);
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
        properties.setValues(parameters);
    }
    
    @Override
    public ConfigurablePropertyMap getProperties() {
        return properties;
    }
    
    /*---------------------------------------------------------------------------------------------
     * VALID STRUCTURES
     *-------------------------------------------------------------------------------------------*/

    public static final List<String> VALID_STRUCTURES = Arrays.asList(new String[] {
        "Images", "Sizes", "Virtual Networks", "Regions", "Storage Accounts", "Affinity Groups", "Cloud Services", "Virtual Machines"
    });
    
    /*---------------------------------------------------------------------------------------------
     * IMPLEMENTATION METHODS
     *-------------------------------------------------------------------------------------------*/

    @Override
    public Count count(BridgeRequest request) throws BridgeError {
        String structure = request.getStructure();
        
        if (!VALID_STRUCTURES.contains(structure)) {
            throw new BridgeError("Invalid Structure: '" + structure + "' is not a valid structure");
        }
        
        AzureQualificationParser parser = new AzureQualificationParser();
        String query = parser.parse(request.getQuery(),request.getParameters());
        
        // Subscription ID should be passed in between square brackets as the first
        // argument. Ex: [abc-123-xyz]. Put all matches of square brackets in
        // an array (in case other query values have square brackets). Since 
        // the Subscription ID will be the first match, we will grab the first
        // element of the array to get it.
        
        ArrayList<String> apiParams = new ArrayList<String>();
        Pattern p = Pattern.compile("\\[(.*?)\\]");
        Matcher m = p.matcher(query);
        
        // Adding all content between square brackets into an array.
        while(m.find()) {
            apiParams.add(m.group(1));
        }
        
        String url = null;

        if (apiParams.isEmpty()) {
            throw new BridgeError("Subscription ID must be provided as the first query.");
        } else {
            url = String.format("https://management.core.usgovcloudapi.net/%s", apiParams.get(0));
        }

        if (structure.equals("Images")) {
            url = String.format("%s/services/images", url);
        } else if (structure.equals("Sizes")) {
            url = String.format("%s/rolesizes", url);
        } else if (structure.equals("Virtual Networks")) {
            url = String.format("%s/services/networking/virtualnetwork", url);
        } else if (structure.equals("Regions")) {
            url = String.format("%s/locations", url);
        } else if (structure.equals("Storage Accounts")) {
            url = String.format("%s/services/storageservices", url);
        } else if (structure.equals("Affinity Groups")) {
            url = String.format("%s/affinitygroups", url);
        } else if (structure.equals("Cloud Services")) {
            url = String.format("%s/services/hostedservices", url);
        } else if (structure.equals("Virtual Machines")) {
            url = String.format("%s/services/hostedservices/%s?embed-detail=true", url, apiParams.get(1));
        }

        JSONArray outputArray = null;
        JSONObject jsonOutput = null;
        
        try {
            String response = processGetRequest(new URL(url), this.keystorePath, this.keystorePassword);
            // Parse XML response to JSON
            jsonOutput = XML.toJSONObject(response);
        } catch (UnrecoverableKeyException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        } catch (MalformedURLException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        } catch (KeyManagementException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        } catch (KeyStoreException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        } catch (NoSuchAlgorithmException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        } catch (IOException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        }

        if (structure.equals("Images")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("Images").getJSONArray("OSImage");
        } else if (structure.equals("Sizes")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("RoleSizes").getJSONArray("RoleSize");
        } else if (structure.equals("Virtual Networks")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("VirtualNetworkSites").getJSONArray("VirtualNetworkSite");
        } else if (structure.equals("Regions")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("Locations").getJSONArray("Location");
        } else if (structure.equals("Storage Accounts")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("StorageServices").getJSONArray("StorageService");
        } else if (structure.equals("Affinity Groups")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("AffinityGroups").getJSONArray("AffinityGroup");
        } else if (structure.equals("Cloud Services")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("HostedServices").getJSONArray("HostedService");
        } else if (structure.equals("Virtual Machines")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("HostedService").getJSONObject("Deployments")
                                      .getJSONObject("Deployment").getJSONObject("RoleInstanceList").getJSONArray("RoleInstance");
        }

        Pattern pattern = Pattern.compile("([\"\"])(?:(?=(\\\\?))\\2.)*?\\1");
        Matcher matcher = pattern.matcher(query);

        while (matcher.find()) {
            String key = matcher.group();
            // used to replace the outside quotes from the key value
            key = key.replaceAll("^\"|\"$", "");
            if (!key.equals("*")) {
                // While there is still a value contained within double quotes
                matcher.find();
                String value = matcher.group();
                // used to replace the outside quotes from the value
                value = value.replaceAll("^\"|\"$", "");
                
                // Array to get the index of jsonObject that doesn't match
                // the query. This will help when we remove from jsonOutput
                // as elements shift.
                List<Integer> indices = new ArrayList<Integer>();
                String rec = null;
                for (int i = 0; i < outputArray.length(); i++) {
                    if (outputArray.getJSONObject(i).has(key)) {
                        rec = outputArray.getJSONObject(i).get(key).toString();
                    }

                    if (!value.equals(rec)) {
                        indices.add(i);
                    }
                }

                Collections.sort(indices, Collections.reverseOrder());
                for (int i : indices) {
                    outputArray.remove(i);
                }
            }
        }

        Long count;
        count = Long.valueOf(outputArray.length() );

        return new Count(count);
    }

    @Override
    public Record retrieve(BridgeRequest request) throws BridgeError {
        String structure = request.getStructure();
        
        if (!VALID_STRUCTURES.contains(structure)) {
            throw new BridgeError("Invalid Structure: '" + structure + "' is not a valid structure");
        }
        
        List<String> fields = request.getFields();
        
        if ( fields == null) {
            throw new BridgeError("No Fields entered. You must enter at least one field.");
        }
        
        AzureQualificationParser parser = new AzureQualificationParser();
        String query = parser.parse(request.getQuery(),request.getParameters());
        
        // Subscription ID should be passed in between square brackets as the first
        // argument. Ex: [abc-123-xyz]. Put all matches of square brackets in
        // an array (in case other query values have square brackets). Since 
        // the Subscription ID will be the first match, we will grab the first
        // element of the array to get it.
        
        ArrayList<String> apiParams = new ArrayList<String>();
        Pattern p = Pattern.compile("\\[(.*?)\\]");
        Matcher m = p.matcher(query);
        
        // Adding all content between square brackets into an array.
        while(m.find()) {
            apiParams.add(m.group(1));
        }
        
        String url = null;

        if (apiParams.isEmpty()) {
            throw new BridgeError("Subscription ID must be provided as the first query.");
        } else {
            url = String.format("https://management.core.usgovcloudapi.net/%s", apiParams.get(0));
        }

        if (structure.equals("Images")) {
            url = String.format("%s/services/images", url);
        } else if (structure.equals("Sizes")) {
            url = String.format("%s/rolesizes", url);
        } else if (structure.equals("Virtual Networks")) {
            url = String.format("%s/services/networking/virtualnetwork", url);
        } else if (structure.equals("Regions")) {
            url = String.format("%s/locations", url);
        } else if (structure.equals("Storage Accounts")) {
            url = String.format("%s/services/storageservices", url);
        } else if (structure.equals("Affinity Groups")) {
            url = String.format("%s/affinitygroups", url);
        } else if (structure.equals("Cloud Services")) {
            url = String.format("%s/services/hostedservices", url);
        } else if (structure.equals("Virtual Machines")) {
            url = String.format("%s/services/hostedservices/%s?embed-detail=true", url, apiParams.get(1));
        }
        
        JSONArray outputArray = null;
        JSONObject jsonOutput = null;
        
        try {
            String response = processGetRequest(new URL(url), this.keystorePath, this.keystorePassword);
            // Parse XML response to JSON
            jsonOutput = XML.toJSONObject(response);
        } catch (UnrecoverableKeyException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        } catch (MalformedURLException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        } catch (KeyManagementException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        } catch (KeyStoreException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        } catch (NoSuchAlgorithmException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        } catch (IOException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        }
        
        if (structure.equals("Images")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("Images").getJSONArray("OSImage");
        } else if (structure.equals("Sizes")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("RoleSizes").getJSONArray("RoleSize");
        } else if (structure.equals("Virtual Networks")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("VirtualNetworkSites").getJSONArray("VirtualNetworkSite");
        } else if (structure.equals("Regions")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("Locations").getJSONArray("Location");
        } else if (structure.equals("Storage Accounts")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("StorageServices").getJSONArray("StorageService");
        } else if (structure.equals("Affinity Groups")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("AffinityGroups").getJSONArray("AffinityGroup");
        } else if (structure.equals("Cloud Services")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("HostedServices").getJSONArray("HostedService");
        } else if (structure.equals("Virtual Machines")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("HostedService").getJSONObject("Deployments")
                                      .getJSONObject("Deployment").getJSONObject("RoleInstanceList").getJSONArray("RoleInstance");
        }

        Pattern pattern = Pattern.compile("([\"\"])(?:(?=(\\\\?))\\2.)*?\\1");
        Matcher matcher = pattern.matcher(query);

        while (matcher.find()) {
            String key = matcher.group();
            // used to replace the outside quotes from the key value
            key = key.replaceAll("^\"|\"$", "");
            if (!key.equals("*")) {
                // While there is still a value contained within double quotes
                matcher.find();
                String value = matcher.group();
                // used to replace the outside quotes from the value
                value = value.replaceAll("^\"|\"$", "");
                
                // Array to get the index of jsonObject that doesn't match
                // the query. This will help when we remove from jsonOutput
                // as elements shift.
                List<Integer> indices = new ArrayList<Integer>();
                String rec = null;
                for (int i = 0; i < outputArray.length(); i++) {
                    if (outputArray.getJSONObject(i).has(key)) {
                        rec = outputArray.getJSONObject(i).getString(key);
                    }

                    if (!value.equals(rec)) {
                        indices.add(i);
                    }
                }

                Collections.sort(indices, Collections.reverseOrder());
                for (int i : indices) {
                    outputArray.remove(i);
                }
            }
        }
        
        Record record;

        if (outputArray.length() > 1) {
            throw new BridgeError("Multiple results matched an expected single match query");
        } else if (outputArray.length() == 0) {
            record = new Record(null);
        } else {
            JSONObject result = outputArray.getJSONObject(0);
            Map<String,Object> recordMap = new LinkedHashMap<String,Object>();
            if (fields == null) {
                record = new Record(null);
            } else {
                for (String field: fields) {
                    recordMap.put(field, result.get(field).toString());
                }
                record = new Record(recordMap);
            }
        }
        
        return record;
    }

    @Override
    public RecordList search(BridgeRequest request) throws BridgeError {
        String structure = request.getStructure();
        Map<String,String> metadata = BridgeUtils.normalizePaginationMetadata(request.getMetadata());
        
        if (!VALID_STRUCTURES.contains(structure)) {
            throw new BridgeError("Invalid Structure: '" + structure + "' is not a valid structure");
        }
        
        List<String> fields = request.getFields();
        
        if ( fields == null) {
            throw new BridgeError("No Fields entered. You must enter at least one field.");
        }
        
        AzureQualificationParser parser = new AzureQualificationParser();
        String query = parser.parse(request.getQuery(),request.getParameters());
        
        // Subscription ID should be passed in between square brackets as the first
        // argument. Ex: [abc-123-xyz]. Put all matches of square brackets in
        // an array (in case other query values have square brackets). Since 
        // the Subscription ID will be the first match, we will grab the first
        // element of the array to get it.
        
        ArrayList<String> apiParams = new ArrayList<String>();
        Pattern p = Pattern.compile("\\[(.*?)\\]");
        Matcher m = p.matcher(query);
        
        // Adding all content between square brackets into an array.
        while(m.find()) {
            apiParams.add(m.group(1));
        }
        
        String url = null;

        if (apiParams.isEmpty()) {
            throw new BridgeError("Subscription ID must be provided as the first query.");
        } else {
            url = String.format("https://management.core.usgovcloudapi.net/%s", apiParams.get(0));
        }

        if (structure.equals("Images")) {
            url = String.format("%s/services/images", url);
        } else if (structure.equals("Sizes")) {
            url = String.format("%s/rolesizes", url);
        } else if (structure.equals("Virtual Networks")) {
            url = String.format("%s/services/networking/virtualnetwork", url);
        } else if (structure.equals("Regions")) {
            url = String.format("%s/locations", url);
        } else if (structure.equals("Storage Accounts")) {
            url = String.format("%s/services/storageservices", url);
        } else if (structure.equals("Affinity Groups")) {
            url = String.format("%s/affinitygroups", url);
        } else if (structure.equals("Cloud Services")) {
            url = String.format("%s/services/hostedservices", url);
        } else if (structure.equals("Virtual Machines")) {
            url = String.format("%s/services/hostedservices/%s?embed-detail=true", url, apiParams.get(1));
        }
        
        JSONArray outputArray = null;
        JSONObject jsonOutput = null;
        
        try {
            String response = processGetRequest(new URL(url), this.keystorePath, this.keystorePassword);
            // Parse XML response to JSON
            jsonOutput = XML.toJSONObject(response);
        } catch (UnrecoverableKeyException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        } catch (MalformedURLException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        } catch (KeyManagementException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        } catch (KeyStoreException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        } catch (NoSuchAlgorithmException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        } catch (IOException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        }
        
        if (structure.equals("Images")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("Images").getJSONArray("OSImage");
        } else if (structure.equals("Sizes")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("RoleSizes").getJSONArray("RoleSize");
        } else if (structure.equals("Virtual Networks")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("VirtualNetworkSites").getJSONArray("VirtualNetworkSite");
        } else if (structure.equals("Regions")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("Locations").getJSONArray("Location");
        } else if (structure.equals("Storage Accounts")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("StorageServices").getJSONArray("StorageService");
        } else if (structure.equals("Affinity Groups")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("AffinityGroups").getJSONArray("AffinityGroup");
        } else if (structure.equals("Cloud Services")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("HostedServices").getJSONArray("HostedService");
        } else if (structure.equals("Virtual Machines")) {
            outputArray = (JSONArray) jsonOutput.getJSONObject("HostedService").getJSONObject("Deployments")
                                      .getJSONObject("Deployment").getJSONObject("RoleInstanceList").getJSONArray("RoleInstance");
        }
        
        Pattern pattern = Pattern.compile("([\"\"])(?:(?=(\\\\?))\\2.)*?\\1");
        Matcher matcher = pattern.matcher(query);

        while (matcher.find()) {
            String key = matcher.group();
            // used to replace the outside quotes from the key value
            key = key.replaceAll("^\"|\"$", "");
            if (!key.equals("*")) {
                // While there is still a value contained within double quotes
                matcher.find();
                String value = matcher.group();
                // used to replace the outside quotes from the value
                value = value.replaceAll("^\"|\"$", "");
                
                // Array to get the index of jsonObject that doesn't match
                // the query. This will help when we remove from jsonOutput
                // as elements shift.
                List<Integer> indices = new ArrayList<Integer>();
                String rec = null;
                for (int i = 0; i < outputArray.length(); i++) {
                    if (outputArray.getJSONObject(i).has(key)) {
                        rec = outputArray.getJSONObject(i).getString(key);
                    }

                    if (!value.equals(rec)) {
                        indices.add(i);
                    }
                }

                Collections.sort(indices, Collections.reverseOrder());
                for (int i : indices) {
                    outputArray.remove(i);
                }
            }
        }

        List<Record> records = new ArrayList<Record>();
        
        for (int i=0; i < outputArray.length(); i++) {
            Map<String,Object> map = new HashMap<String,Object>();
            JSONObject recordObject = (JSONObject)outputArray.getJSONObject(i);
            Iterator<String> keysItr = recordObject.keys();
            while(keysItr.hasNext()) {
                String key = keysItr.next();
                Object value = recordObject.get(key).toString();
                map.put(key, value);
            }
            records.add(new Record(map));
        }

        // Returning the response
        return new RecordList(fields, records, metadata);
    }
    
    private static KeyStore getKeyStore(String keyStoreName, String password) throws IOException, BridgeError {
        KeyStore ks = null;
        FileInputStream fis = null;
        try {
            ks = KeyStore.getInstance("JKS");
            char[] passwordArray = password.toCharArray();
            fis = new java.io.FileInputStream(keyStoreName);
            ks.load(fis, passwordArray);
            fis.close();

        } catch (KeyStoreException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        } catch (NoSuchAlgorithmException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        } catch (CertificateException ex) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Azure");
        } 

        finally {
            if (fis != null) {
                fis.close();
            }
        }
        return ks;
    }
    
    private static SSLSocketFactory getSSLSocketFactory(String keyStoreName, String password) throws UnrecoverableKeyException, KeyStoreException, NoSuchAlgorithmException, KeyManagementException, IOException, BridgeError {
        KeyStore ks = getKeyStore(keyStoreName, password);
        KeyManagerFactory keyManagerFactory = KeyManagerFactory.getInstance("SunX509");
        keyManagerFactory.init(ks, password.toCharArray());

          SSLContext context = SSLContext.getInstance("TLS");
          context.init(keyManagerFactory.getKeyManagers(), null, new SecureRandom());

          return context.getSocketFactory();
    }
    
    private static String processGetRequest(URL url, String keyStore, String keyStorePassword) throws UnrecoverableKeyException, KeyManagementException, KeyStoreException, NoSuchAlgorithmException, IOException, BridgeError {
        SSLSocketFactory sslFactory = getSSLSocketFactory(keyStore, keyStorePassword);
        HttpsURLConnection con = (HttpsURLConnection) url.openConnection();
        con.setSSLSocketFactory(sslFactory);
        con.setRequestMethod("GET");
        con.addRequestProperty("x-ms-version", "2015-04-01");
        String response;
        InputStream responseStream = (InputStream) con.getContent();
        response = getStringFromInputStream(responseStream);
        return response;
    }
    
    private static String getStringFromInputStream(InputStream is) {

        BufferedReader br = null;
        StringBuilder sb = new StringBuilder();

        String line;
        try {

            br = new BufferedReader(new InputStreamReader(is));
            while ((line = br.readLine()) != null) {
                sb.append(line);
            }

        } catch (IOException e) {
        } finally {
            if (br != null) {
                try {
                    br.close();
                } catch (IOException e) {
                }
            }
        }

        return sb.toString();
    }

}
