/**
 * Unit tests for AT_ProductCogsBatch.
 *
 * Covers:
 *  - the full batch run against a real open CPQ quote line (start -> execute -> finish),
 *    which copies the product's regional total onto Region_COGS__c and marks staging Success;
 *  - products with no open quote lines, whose Running staging records are marked Skipped in finish();
 *  - execute() called directly with in-memory scopes for the unmapped-region, DML-failure and
 *    unexpected-exception paths.
 */
@isTest
private class AT_ProductCogsBatchTest {

    @testSetup
    static void setupData() {
        Product2 product = new Product2(Name = 'COGS Batch Test Product', ATFE_Cost__c = 100, IsActive = true);
        insert product;

        Id naRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('ATI Accounts').getRecordTypeId();
        Account acc = new Account(
            Name = 'COGS Batch Test Account',
            RecordTypeId = naRecordTypeId,
            Region__c = 'NA',
            Sub_Region__c = 'USA',
            ATFE_SalesOrgName__c = 'Channel',
            ATFE_AccountType__c = 'Partner',
            BillingCountry = 'United States',
            BillingCity = 'billing city',
            BillingStreet = 'billing street',
            BillingPostalCode = 'billing postal code',
            BillingState = 'TX'
        );
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'COGS Batch Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospect/Qualification',
            CloseDate = Date.today().addDays(30),
            Required_Delivery_Date__c = Date.today().addDays(60)
        );
        insert opp;

        ATFE_PLMUpdateOnQuickQuoteHelper.DoNotRunATFE_SBBQQuoteLineTrigger = true;
        // Non-primary quote => COGS_Sync__c on its lines evaluates to TRUE.
        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            ATFE_Quote_Name__c = 'COGS Batch Test Quote',
            ATFE_SPQ_Approved__c = false,
            SBQQ__Primary__c = false,
            SBQQ__Opportunity2__c = opp.Id,
            SBQQ__Account__c = acc.Id
        );
        insert quote;

        insert new SBQQ__QuoteLine__c(
            SBQQ__Product__c = product.Id,
            SBQQ__Quantity__c = 1,
            MSRP_Price__c = 500,
            SBQQ__Quote__c = quote.Id,
            Region_COGS__c = 0
        );
        ATFE_PLMUpdateOnQuickQuoteHelper.DoNotRunATFE_SBBQQuoteLineTrigger = false;
    }

    private static Product2 getProduct() {
        return [SELECT Id, Total_NA__c FROM Product2 WHERE Name = 'COGS Batch Test Product' LIMIT 1];
    }

    private static COGSUpdateStagingRecord__c newStaging(String productId) {
        return new COGSUpdateStagingRecord__c(ProductId__c = productId, ProcessingStatus__c = 'Holding');
    }

    private static Integer countByStatus(String status) {
        return [SELECT count() FROM COGSUpdateStagingRecord__c WHERE ProcessingStatus__c = :status];
    }

    /** Builds an in-memory quote line (relationship fields can't be set any other way). */
    private static SBQQ__QuoteLine__c buildLine(Id lineId, Id productId, Object quoteRel) {
        return buildLine(lineId, productId, quoteRel, true);
    }

    private static SBQQ__QuoteLine__c buildLine(Id lineId, Id productId, Object quoteRel, Boolean includeProductRel) {
        Map<String, Object> raw = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'SBQQ__QuoteLine__c' },
            'Id' => lineId,
            'SBQQ__Product__c' => productId,
            'SBQQ__Quote__r' => quoteRel
        };
        if (includeProductRel) {
            raw.put('SBQQ__Product__r', new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'Product2' },
                'Id' => productId,
                'Total_NA__c' => 42,
                'Total_EMEA__c' => 43,
                'Total_APAC__c' => 44,
                'Total_CSA__c' => 45
            });
        }
        return (SBQQ__QuoteLine__c) JSON.deserialize(JSON.serialize(raw), SBQQ__QuoteLine__c.class);
    }

    private static Map<String, Object> quoteRel(String region) {
        return new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'SBQQ__Quote__c' },
            'Quote_To_Region__c' => region
        };
    }

    private static Id fakeQuoteLineId() {
        return Id.valueOf(SBQQ__QuoteLine__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
    }

    @isTest
    static void batch_syncsOpenQuoteLinesAndMarksSuccess() {
        Product2 product = getProduct();
        insert newStaging(product.Id);

        Test.startTest();
        AT_ProductCogsBatch batch = new AT_ProductCogsBatch();
        System.assert(batch.productIds.contains(product.Id), 'Constructor should collect product ids from Holding staging');
        System.assertEquals(1, countByStatus('Running'), 'Constructor should move Holding staging records to Running');
        Database.executeBatch(batch, 200);
        Test.stopTest();

        SBQQ__QuoteLine__c line = [SELECT Region_COGS__c FROM SBQQ__QuoteLine__c WHERE SBQQ__Product__c = :product.Id LIMIT 1];
        Decimal expected = product.Total_NA__c == null ? null : product.Total_NA__c.setScale(2);
        System.assertEquals(expected, line.Region_COGS__c, 'Region_COGS__c should be synced from the NA regional total');
        System.assertEquals(1, countByStatus('Success'), 'Staging record should be marked Success');
        System.assertEquals(0, countByStatus('Running'), 'No staging records should be left Running');
    }

    @isTest
    static void batch_productWithoutQuoteLines_marksSkipped() {
        Product2 other = new Product2(Name = 'COGS Batch Product Without Lines', ATFE_Cost__c = 10, IsActive = true);
        insert other;
        insert new List<COGSUpdateStagingRecord__c>{ newStaging(other.Id), newStaging(other.Id) };

        Test.startTest();
        Database.executeBatch(new AT_ProductCogsBatch(), 200);
        Test.stopTest();

        System.assertEquals(2, countByStatus('Skipped'), 'Staging records with no open quote lines are Skipped in finish()');
        System.assertEquals(0, countByStatus('Running'), 'No staging records should be left Running');
    }

    @isTest
    static void execute_unmappedRegion_updatesNothing() {
        Product2 product = getProduct();
        insert newStaging(product.Id);

        Test.startTest();
        AT_ProductCogsBatch batch = new AT_ProductCogsBatch();
        batch.execute(null, new List<SBQQ__QuoteLine__c>{
            buildLine(fakeQuoteLineId(), product.Id, quoteRel('UNKNOWN'))
        });
        Test.stopTest();

        System.assertEquals(0, batch.failureCount, 'Lines with an unmapped region are skipped, not failed');
        System.assertEquals(1, countByStatus('Running'), 'Staging status is untouched when nothing is updated');
    }

    @isTest
    static void execute_dmlFailure_isCounted() {
        Product2 product = getProduct();
        insert newStaging(product.Id);

        Test.startTest();
        AT_ProductCogsBatch batch = new AT_ProductCogsBatch();
        // The quote line id doesn't exist, so the partial-success update reports a failure.
        batch.execute(null, new List<SBQQ__QuoteLine__c>{
            buildLine(fakeQuoteLineId(), product.Id, quoteRel('EMEA'))
        });
        Test.stopTest();

        System.assertEquals(1, batch.failureCount, 'The failed quote line update should be counted');
        System.assertEquals(1, batch.failureMessages.size(), 'The DML error should be recorded');
        System.assertEquals(false, ATFE_PLMUpdateOnQuickQuoteHelper.DoNotRunATFE_SBBQQuoteLineTrigger,
            'The quote line trigger bypass flag must be reset after the update');
    }

    @isTest
    static void execute_realLineSuccess_marksStagingSuccess() {
        Product2 product = getProduct();
        insert newStaging(product.Id);
        SBQQ__QuoteLine__c realLine = [SELECT Id FROM SBQQ__QuoteLine__c WHERE SBQQ__Product__c = :product.Id LIMIT 1];

        Test.startTest();
        AT_ProductCogsBatch batch = new AT_ProductCogsBatch();
        batch.execute(null, new List<SBQQ__QuoteLine__c>{
            buildLine(realLine.Id, product.Id, quoteRel('APAC'))
        });
        Test.stopTest();

        System.assertEquals(0, batch.failureCount, 'Update of an existing line should succeed');
        System.assertEquals(44, [SELECT Region_COGS__c FROM SBQQ__QuoteLine__c WHERE Id = :realLine.Id].Region_COGS__c,
            'Region_COGS__c should take the APAC total from the scope record');
        System.assertEquals(1, countByStatus('Success'), 'Staging record should be marked Success');
    }

    @isTest
    static void execute_unexpectedException_failsChunkStaging() {
        Product2 product = getProduct();
        insert newStaging(product.Id);

        Test.startTest();
        AT_ProductCogsBatch batch = new AT_ProductCogsBatch();
        // Mapped region but no SBQQ__Product__r -> .get() on null throws inside execute().
        batch.execute(null, new List<SBQQ__QuoteLine__c>{
            buildLine(fakeQuoteLineId(), product.Id, quoteRel('NA'), false)
        });
        Test.stopTest();

        System.assertEquals(1, batch.failureCount, 'The unexpected exception should be counted');
        System.assert(batch.failureMessages[0].startsWith('execute:'), 'The exception should be recorded against execute');
        System.assertEquals(1, countByStatus('Failed'), 'Staging records for the chunk should be marked Failed');
    }
}
