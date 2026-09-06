/**
 * Migrated from ProductTrigger (Product2, after update). When a Product2 is updated but none of
 * its cost / regional total fields change (i.e. some other attribute such as availability
 * changed), calls ATFE_SBBQQuoteLineTriggerHandler.EOSProductHandler to re-sync the EOS
 * product/service flags on every quote referencing that product. Runs only for Products whose
 * RecordType DeveloperName is not JP_Product (and, as in the original source, only for Products
 * with no record type set).
 */
public class TA_Product2_SyncQuoteEosFlags implements TriggerAction.AfterUpdate {

    public void afterUpdate(List<Product2> triggerNew, List<Product2> triggerOld) {
        Map<Id, Product2> oldMap = new Map<Id, Product2>(triggerOld);
        Set<Id> productIds = new Set<Id>();

        for (Product2 p : TA_Product2_TriggerHelper.excludeJpProduct(triggerNew)) {
            // Migrated as-is from ProductTrigger: the original source only considered Products
            // with no record type, and only when none of the regional COGS values changed.
            if (p.RecordTypeId != null) {
                continue;
            }

            Product2 oldProduct = oldMap.get(p.Id);
            if (p.ATFE_Cost__c == oldProduct.ATFE_Cost__c
                && p.Total_NA__c == oldProduct.Total_NA__c
                && p.Total_EMEA__c == oldProduct.Total_EMEA__c
                && p.Total_APAC__c == oldProduct.Total_APAC__c
                && p.Total_CSA__c == oldProduct.Total_CSA__c) {
                productIds.add(p.Id);
            }
        }

        if (!productIds.isEmpty()) {
            ATFE_SBBQQuoteLineTriggerHandler.EOSProductHandler(productIds);
        }
    }
}