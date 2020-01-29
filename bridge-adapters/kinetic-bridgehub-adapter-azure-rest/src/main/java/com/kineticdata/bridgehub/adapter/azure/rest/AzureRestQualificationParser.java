package com.kineticdata.bridgehub.adapter.azure.rest;

import com.kineticdata.bridgehub.adapter.BridgeError;
import com.kineticdata.bridgehub.adapter.QualificationParser;
import java.util.HashMap;
import java.util.Map;
import org.slf4j.LoggerFactory;

public class AzureRestQualificationParser extends QualificationParser {
     /** Defines the logger */
    protected static final org.slf4j.Logger logger 
        = LoggerFactory.getLogger(AzureRestAdapter.class);
    
    protected Map<String, String> getParameters (String queryString)
        throws BridgeError {
      
        Map<String, String> parameters = new HashMap<>();

        // Return empyt map if no query was provided from reqeust.
        if (!queryString.isEmpty()) {
            String[] queries = queryString.split("&(?=[^&]*?=)");
            for (String query : queries) {
                // Split the query on the = to determine the field/value key-pair. 
                // Anything before the first = is considered to be the field and 
                // anything after (including more = signs if there are any) is 
                // considered to be part of the value
                String[] str_array = query.split("=",2);
                if (str_array.length == 2) {
                    parameters.merge(str_array[0].trim(), str_array[1].trim(), 
                        (prev, curr) -> {
                            return String.join(",", prev, curr);
                        }
                    );
                } else if (str_array.length == 1) {
                    parameters.put(str_array[0].trim(), null);
                } else {
                    logger.debug("%s has a parameter that was unexpected.",
                        queryString);
                }
            }
        }
        return parameters;
    }
    
    public String encodeParameter(String name, String value) {
        return value;
    }
}
