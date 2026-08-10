@isTest
private class TA_Account_LocTzInsert_Test {

    @isTest
    static void test_stampsTimezoneUpdatedOnBeforeInsertForRegularAccount() {
        Id fakeId = TriggerTestUtility.getFakeId(Account.SObjectType);
        Account acc = new Account(Id = fakeId, Name = 'Test Account');

        Test.startTest();
        new TA_Account_LocTzInsert().beforeInsert(new List<Account>{ acc });
        Test.stopTest();

        System.assertEquals(true, acc.Timezone_Updated__c, 'Timezone_Updated__c should be stamped true on insert');
    }

    @isTest
    static void test_skipsRecordTypeStampOnBeforeInsertForJpAccounts() {
        Map<String, Schema.RecordTypeInfo> rtByDeveloperName = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        if (!rtByDeveloperName.containsKey('JP_Accounts')) {
            return;
        }

        Id fakeId = TriggerTestUtility.getFakeId(Account.SObjectType);
        Account acc = new Account(
            Id = fakeId,
            Name = 'JP Account',
            RecordTypeId = rtByDeveloperName.get('JP_Accounts').getRecordTypeId()
        );

        Test.startTest();
        new TA_Account_LocTzInsert().beforeInsert(new List<Account>{ acc });
        Test.stopTest();

        System.assertEquals(null, acc.Timezone_Updated__c, 'JP_Accounts record type should be excluded from this action');
    }

    @isTest
    static void test_skipsWholeBatchOnBeforeInsertWhenAnyRecordIsFromSansan() {
        Id fakeId1 = TriggerTestUtility.getFakeId(Account.SObjectType);
        Id fakeId2 = TriggerTestUtility.getFakeId(Account.SObjectType);
        Account sansanAcc = new Account(Id = fakeId1, Name = 'Sansan Account', Sansan_CI__Sansan_CompanyId_FK__c = '12345');
        Account otherAcc = new Account(Id = fakeId2, Name = 'Other Account');

        Test.startTest();
        new TA_Account_LocTzInsert().beforeInsert(new List<Account>{ sansanAcc, otherAcc });
        Test.stopTest();

        System.assertEquals(null, otherAcc.Timezone_Updated__c, 'Entire batch should be skipped when any record came from Sansan');
    }

    @isTest
    static void test_afterInsertSkipsCalloutWhenLocationCalloutsIsBypassed() {
        LocationCallouts.skipcallout = true;

        Id fakeId = TriggerTestUtility.getFakeId(Account.SObjectType);
        Account acc = new Account(Id = fakeId, Name = 'Test Account');

        Test.startTest();
        new TA_Account_LocTzInsert().afterInsert(new List<Account>{ acc });
        Test.stopTest();
    }
}
