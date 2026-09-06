public class TA_Product2_TriggerHelper {

    private static Set<Id> excludedRecordTypeIds;

    // Product2 records of the JP_Product record type are excluded from these Product2
    // trigger actions across the board; cached per-transaction so each TriggerAction
    // that calls this doesn't repeat the same RecordType describe.
    public static Set<Id> getExcludedRecordTypeIds() {
        if (excludedRecordTypeIds == null) {
            excludedRecordTypeIds = new Set<Id>();
            Map<String, Schema.RecordTypeInfo> rtMapByDeveloperName = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName();
            if (rtMapByDeveloperName.containsKey('JP_Product')) {
                excludedRecordTypeIds.add(rtMapByDeveloperName.get('JP_Product').getRecordTypeId());
            }
        }
        return excludedRecordTypeIds;
    }

    public static List<Product2> excludeJpProduct(List<Product2> products) {
        Set<Id> excludedIds = getExcludedRecordTypeIds();
        List<Product2> recordsToProcess = new List<Product2>();
        for (Product2 p : products) {
            if (!excludedIds.contains(p.RecordTypeId)) {
                recordsToProcess.add(p);
            }
        }
        return recordsToProcess;
    }
}