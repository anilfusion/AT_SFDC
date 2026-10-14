# Before deploying Log_Type_Execution_Context__c from the branch, update the XML first to below and deploy, and then deploy the branch version:

<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Log_Type_Execution_Context__c</fullName>
    <label>Log Type/Execution Context</label>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Picklist</type>
    <valueSet>
        <restricted>true</restricted>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value>
                <fullName>Test</fullName>
                <default>false</default>
                <label>Test</label>
            </value>
        </valueSetDefinition>
    </valueSet>
</CustomField>


# Before deploying Log_Subtype__c from the branch, update the XML first to below and deploy, and then deploy the branch version:

<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Log_Subtype__c</fullName>
    <label>Log Subtype</label>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Picklist</type>
    <valueSet>
        <restricted>true</restricted>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value>
                <fullName>Test</fullName>
                <default>false</default>
                <label>Test</label>
            </value>
        </valueSetDefinition>
    </valueSet>
</CustomField>