/**
 * Migrated from ProductCogsTrigger (Product2, after update). When a Product2's cost or regional
 * total fields change, enqueues BatchUpdateProductCogs to re-sync Region_COGS__c on the open
 * quote lines that reference that product. Runs only for Products whose RecordType DeveloperName
 * is not JP_Product (and, as in the original source, only for Products with no record type set).
 *
 * An unexpected failure while enqueuing the batch (e.g. a missing/invalid Cogs_Batch_Size label,
 * or the per-transaction async-job ceiling) is captured through the Logger framework and swallowed:
 * this is a best-effort background re-sync and must not roll back the user's Product2 update.
 */
public class TA_Product2_SyncQuoteLineCogs implements TriggerAction.AfterUpdate {

    public void afterUpdate(List<Product2> triggerNew, List<Product2> triggerOld) {
        List<COGSUpdateStagingRecord__c> stagingRecordsToCreate = new List<COGSUpdateStagingRecord__c>();
        try {
            Map<Id, Product2> oldMap = new Map<Id, Product2>(triggerOld);

            for (Product2 newProduct : TA_Product2_TriggerHelper.excludeJpProduct(triggerNew)) {
                // Migrated as-is from ProductCogsTrigger: the original source only considered
                // Products with no record type.
                if (newProduct.RecordTypeId != null) {
                    continue;
                }

                Product2 oldProduct = oldMap.get(newProduct.Id);
                if (newProduct.ATFE_Cost__c != oldProduct.ATFE_Cost__c
                    || newProduct.Total_NA__c != oldProduct.Total_NA__c
                    || newProduct.Total_EMEA__c != oldProduct.Total_EMEA__c
                    || newProduct.Total_APAC__c != oldProduct.Total_APAC__c
                    || newProduct.Total_CSA__c != oldProduct.Total_CSA__c) {
                        stagingRecordsToCreate.add(
                        	new COGSUpdateStagingRecord__c(
                            	ProductId__c = newProduct.Id,
                                ProcessingStatus__c = 'Holding',
                                ChangeAuditRTF__c = generateChangeAuditText(oldProduct, newProduct)
                            )
                        );
                }
            }

            if (!stagingRecordsToCreate.isEmpty()) {
                insert stagingRecordsToCreate;
            }
        } catch (Exception e) {
            // Logger.commitLogs() never throws, so no defensive wrapper is needed here.
            Logger.logApexException(
                e,
                'Apex Trigger',
                'Product COGS Sync',
                triggerNew.isEmpty() ? null : String.valueOf(triggerNew[0].Id),
                new Map<String, Object>{ 'Staging Records' => stagingRecordsToCreate }
            );
            Logger.commitLogs();
        }
    }

    private static String generateChangeAuditText(Product2 oldProduct, Product2 newProduct) {
        String changeAuditStr = '<table border="1" style="width:100%;">';
        changeAuditStr += '<tr><td><b>Attribute</b></td><td><b>Old Value</b></td><td><b>New Value</b></td></tr>';
        if(newProduct.ATFE_Cost__c != oldProduct.ATFE_Cost__c) {
            changeAuditStr += '<tr style="background-color: #D6EEEE;"><td>ATFE_Cost__c</td><td>' + oldProduct.ATFE_Cost__c + '</td><td>' + newProduct.ATFE_Cost__c + '</td>';
        }
        if(newProduct.Total_NA__c != oldProduct.Total_NA__c) {
            changeAuditStr += '<tr><td>Total_NA__c</td><td>' + oldProduct.Total_NA__c + '</td><td>' + newProduct.Total_NA__c + '</td>';
        }
        if(newProduct.Total_EMEA__c != oldProduct.Total_EMEA__c) {
            changeAuditStr += '<tr style="background-color: #D6EEEE;"><td>Total_EMEA__c</td><td>' + oldProduct.Total_EMEA__c + '</td><td>' + newProduct.Total_EMEA__c + '</td>';
        }
        if(newProduct.Total_APAC__c != oldProduct.Total_APAC__c) {
            changeAuditStr += '<tr><td>Total_APAC__c</td><td>' + oldProduct.Total_APAC__c + '</td><td>' + newProduct.Total_APAC__c + '</td>';
        }
        if(newProduct.Total_CSA__c != oldProduct.Total_CSA__c) {
            changeAuditStr += '<tr style="background-color: #D6EEEE;"><td>Total_CSA__c</td><td>' + oldProduct.Total_CSA__c + '</td><td>' + newProduct.Total_CSA__c + '</td>';
        }
        changeAuditStr += '</table>';
        return changeAuditStr;
    }
}