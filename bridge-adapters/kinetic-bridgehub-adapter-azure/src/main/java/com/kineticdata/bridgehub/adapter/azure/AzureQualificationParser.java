package com.kineticdata.bridgehub.adapter.azure;

import com.kineticdata.bridgehub.adapter.QualificationParser;

/**
 *
 */
public class AzureQualificationParser extends QualificationParser {
    public String encodeParameter(String name, String value) {
        return value;
    }
}
