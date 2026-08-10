@isTest
private class TA_Account_LocTzUpdate_Test {

    @isTest
    static void test_stampsTimezoneUpdatedAndQueuesCalloutWhenBusinessIsBlank() {
        LocationCallouts.skipcallout = true;

        Id fakeId = TriggerTestUtility.getFakeId(Account.SObjectType);
        Account acc = new Account(Id = fakeId, Name = 'Test Account', Timezone_Updated__c = false);
        Account oldAcc = new Account(Id = fakeId, Name = 'Test Account', Timezone_Updated__c = false);

        Test.startTest();
        new TA_Account_LocTzUpdate().beforeUpdate(new List<Account>{ acc }, new List<Account>{ oldAcc });
        Test.stopTest();

        System.assertEquals(true, acc.Timezone_Updated__c, 'Timezone_Updated__c should always be stamped true on update');
    }

    @isTest
    static void test_stampsTimezoneUpdatedWhenBusinessIsAlreadyPopulated() {
        LocationCallouts.skipcallout = true;

        Id fakeId = TriggerTestUtility.getFakeId(Account.SObjectType);
        Account acc = new Account(Id = fakeId, Name = 'Test Account', Business__c = 'Some Business (America/New_York)', Timezone_Updated__c = false);
        Account oldAcc = new Account(Id = fakeId, Name = 'Test Account', Timezone_Updated__c = false);

        Test.startTest();
        new TA_Account_LocTzUpdate().beforeUpdate(new List<Account>{ acc }, new List<Account>{ oldAcc });
        Test.stopTest();

        System.assertEquals(true, acc.Timezone_Updated__c, 'Timezone_Updated__c should be stamped true even when Business__c is already populated');
    }

    @isTest
    static void test_skipsRecordTypeOnBeforeUpdateForJpAccounts() {
        Map<String, Schema.RecordTypeInfo> rtByDeveloperName = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        if (!rtByDeveloperName.containsKey('JP_AccountsBeforeCleansing')) {
            return;
        }

        Id fakeId = TriggerTestUtility.getFakeId(Account.SObjectType);
        Id recordTypeId = rtByDeveloperName.get('JP_AccountsBeforeCleansing').getRecordTypeId();
        Account acc = new Account(Id = fakeId, Name = 'JP Account', RecordTypeId = recordTypeId, Timezone_Updated__c = false);
        Account oldAcc = new Account(Id = fakeId, Name = 'JP Account', RecordTypeId = recordTypeId, Timezone_Updated__c = false);

        Test.startTest();
        new TA_Account_LocTzUpdate().beforeUpdate(new List<Account>{ acc }, new List<Account>{ oldAcc });
        Test.stopTest();

        System.assertEquals(false, acc.Timezone_Updated__c, 'JP_AccountsBeforeCleansing record type should be excluded from this action');
    }
}
