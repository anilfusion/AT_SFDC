/**
 * Unit tests for TA_Product2_SyncQuoteLineCogs.
 *
 * The TriggerAction is exercised directly - afterUpdate() is called with hand-built
 * old / new Product2 lists - so the tests stay independent of Product2 record-type
 * defaults, the read-only regional Total_* formula fields and CPQ quote data.
 * Product2 records are built through JSON.deserialize so the formula fields (and,
 * where needed, RecordTypeId) can be given explicit values.
 *
 * When a Product2 with no record type has a cost / regional total change, the class
 * inserts one COGSUpdateStagingRecord__c (status 'Holding') per changed product, carrying
 * an HTML audit table of the changed attributes. The staging records are later picked up
 * by AT_ProductCogsBatch (launched from the Update COGS UI).
 */
@isTest
private class TA_Product2_SyncQuoteLineCogs_Test {

    private static Integer idSeq = 1;

    private static final String PRODUCT2_PREFIX = Product2.SObjectType.getDescribe().getKeyPrefix();
    private static final String RECORDTYPE_PREFIX = '012';

    private static Id fakeId(String keyPrefix) {
        String suffix = String.valueOf(idSeq++);
        return Id.valueOf(keyPrefix + '0'.repeat(12 - suffix.length()) + suffix);
    }

    /**
     * Builds an in-memory Product2. Total_* are formula fields, so the record is
     * assembled as JSON and deserialized to bypass the "field is not writeable" check.
     */
    private static Product2 buildProduct(
        Id recId, Decimal cost, Decimal na, Decimal emea, Decimal apac, Decimal csa, Id recordTypeId
    ) {
        Map<String, Object> raw = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Product2' },
            'Id' => recId,
            'ATFE_Cost__c' => cost,
            'Total_NA__c' => na,
            'Total_EMEA__c' => emea,
            'Total_APAC__c' => apac,
            'Total_CSA__c' => csa
        };
        if (recordTypeId != null) {
            raw.put('RecordTypeId', recordTypeId);
        }
        return (Product2) JSON.deserialize(JSON.serialize(raw), Product2.class);
    }

    private static void runAction(List<Product2> newList, List<Product2> oldList) {
        Test.startTest();
        new TA_Product2_SyncQuoteLineCogs().afterUpdate(newList, oldList);
        Test.stopTest();
    }

    private static List<COGSUpdateStagingRecord__c> getStagingRecords() {
        return [
            SELECT Id, ProductId__c, ProcessingStatus__c, ChangeAuditRTF__c
            FROM COGSUpdateStagingRecord__c
            ORDER BY ProductId__c
        ];
    }

    @isTest
    static void test_costChange_createsHoldingStagingRecord() {
        Id pid = fakeId(PRODUCT2_PREFIX);
        List<Product2> oldList = new List<Product2>{ buildProduct(pid, 100, 10, 20, 30, 40, null) };
        List<Product2> newList = new List<Product2>{ buildProduct(pid, 250, 10, 20, 30, 40, null) };

        runAction(newList, oldList);

        List<COGSUpdateStagingRecord__c> staging = getStagingRecords();
        System.assertEquals(1, staging.size(), 'A change to ATFE_Cost__c should create one staging record');
        System.assertEquals(String.valueOf(pid), staging[0].ProductId__c, 'Staging record should reference the product');
        System.assertEquals('Holding', staging[0].ProcessingStatus__c, 'New staging records should be in Holding status');
        System.assert(staging[0].ChangeAuditRTF__c.contains('ATFE_Cost__c'), 'Audit text should list the changed cost field');
        System.assert(!staging[0].ChangeAuditRTF__c.contains('Total_NA__c'), 'Audit text should not list unchanged fields');
    }

    @isTest
    static void test_allFieldsChanged_auditListsEveryField() {
        Id pid = fakeId(PRODUCT2_PREFIX);
        List<Product2> oldList = new List<Product2>{ buildProduct(pid, 100, 10, 20, 30, 40, null) };
        List<Product2> newList = new List<Product2>{ buildProduct(pid, 101, 11, 21, 31, 41, null) };

        runAction(newList, oldList);

        List<COGSUpdateStagingRecord__c> staging = getStagingRecords();
        System.assertEquals(1, staging.size(), 'One staging record per changed product');
        String audit = staging[0].ChangeAuditRTF__c;
        for (String fieldName : new List<String>{ 'ATFE_Cost__c', 'Total_NA__c', 'Total_EMEA__c', 'Total_APAC__c', 'Total_CSA__c' }) {
            System.assert(audit.contains(fieldName), 'Audit text should list ' + fieldName);
        }
    }

    @isTest
    static void test_regionalTotalChange_createsStagingRecord() {
        // ATFE_Cost__c unchanged; only Total_CSA__c differs - exercises the later
        // operands of the OR condition.
        Id pid = fakeId(PRODUCT2_PREFIX);
        List<Product2> oldList = new List<Product2>{ buildProduct(pid, 100, 10, 20, 30, 40, null) };
        List<Product2> newList = new List<Product2>{ buildProduct(pid, 100, 10, 20, 30, 99, null) };

        runAction(newList, oldList);

        List<COGSUpdateStagingRecord__c> staging = getStagingRecords();
        System.assertEquals(1, staging.size(), 'A change to a regional total should create a staging record');
        System.assert(staging[0].ChangeAuditRTF__c.contains('Total_CSA__c'), 'Audit text should list Total_CSA__c');
        System.assert(!staging[0].ChangeAuditRTF__c.contains('ATFE_Cost__c'), 'Audit text should not list the unchanged cost');
    }

    @isTest
    static void test_noRelevantChange_createsNothing() {
        Id pid = fakeId(PRODUCT2_PREFIX);
        List<Product2> oldList = new List<Product2>{ buildProduct(pid, 100, 10, 20, 30, 40, null) };
        List<Product2> newList = new List<Product2>{ buildProduct(pid, 100, 10, 20, 30, 40, null) };

        runAction(newList, oldList);

        System.assertEquals(0, getStagingRecords().size(), 'No cost / total change should not create staging records');
    }

    @isTest
    static void test_multipleProducts_onlyChangedProductsStaged() {
        Id changedA = fakeId(PRODUCT2_PREFIX);
        Id changedB = fakeId(PRODUCT2_PREFIX);
        Id unchanged = fakeId(PRODUCT2_PREFIX);
        List<Product2> oldList = new List<Product2>{
            buildProduct(changedA, 100, 10, 20, 30, 40, null),
            buildProduct(changedB, 100, 10, 20, 30, 40, null),
            buildProduct(unchanged, 100, 10, 20, 30, 40, null)
        };
        List<Product2> newList = new List<Product2>{
            buildProduct(changedA, 150, 10, 20, 30, 40, null),
            buildProduct(changedB, 100, 10, 20, 30, 77, null),
            buildProduct(unchanged, 100, 10, 20, 30, 40, null)
        };

        runAction(newList, oldList);

        Set<String> stagedProductIds = new Set<String>();
        for (COGSUpdateStagingRecord__c s : getStagingRecords()) {
            stagedProductIds.add(s.ProductId__c);
        }
        System.assertEquals(2, stagedProductIds.size(), 'Only the two changed products should be staged');
        System.assert(stagedProductIds.contains(String.valueOf(changedA)), 'Changed product A should be staged');
        System.assert(stagedProductIds.contains(String.valueOf(changedB)), 'Changed product B should be staged');
        System.assert(!stagedProductIds.contains(String.valueOf(unchanged)), 'Unchanged product should not be staged');
    }

    @isTest
    static void test_productWithRecordType_isSkipped() {
        // Migrated behaviour: only Products with no record type are processed.
        Id pid = fakeId(PRODUCT2_PREFIX);
        Id rtId = fakeId(RECORDTYPE_PREFIX);
        List<Product2> oldList = new List<Product2>{ buildProduct(pid, 100, 10, 20, 30, 40, rtId) };
        List<Product2> newList = new List<Product2>{ buildProduct(pid, 250, 10, 20, 30, 40, rtId) };

        runAction(newList, oldList);

        System.assertEquals(0, getStagingRecords().size(), 'A Product with a record type set should be skipped');
    }

    @isTest
    static void test_unexpectedError_isSwallowed() {
        // triggerOld does not contain the new product, so oldMap.get() returns null and the
        // comparison throws. The action must log and swallow it, never failing the update.
        Id pid = fakeId(PRODUCT2_PREFIX);
        List<Product2> oldList = new List<Product2>{ buildProduct(fakeId(PRODUCT2_PREFIX), 100, 10, 20, 30, 40, null) };
        List<Product2> newList = new List<Product2>{ buildProduct(pid, 250, 10, 20, 30, 40, null) };

        Exception thrown;
        try {
            runAction(newList, oldList);
        } catch (Exception e) {
            thrown = e;
        }

        System.assertEquals(null, thrown, 'Exceptions must be captured by the action, not rethrown');
        System.assertEquals(0, getStagingRecords().size(), 'No staging records should be created on failure');
    }

    @isTest
    static void test_helper_excludeJpProduct_passesThroughNonJpProducts() {
        List<Product2> input = new List<Product2>{
            buildProduct(fakeId(PRODUCT2_PREFIX), 100, 10, 20, 30, 40, null),
            buildProduct(fakeId(PRODUCT2_PREFIX), 100, 10, 20, 30, 40, null)
        };

        Test.startTest();
        List<Product2> result = TA_Product2_TriggerHelper.excludeJpProduct(input);
        Test.stopTest();

        System.assertEquals(input.size(), result.size(),
            'Products that are not the JP_Product record type should pass through unchanged');
    }
}
