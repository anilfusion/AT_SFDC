@isTest
private class TA_Account_TzFromBusiness_Test {

    @isTest
    static void test_parsesTimeZoneNameFromBusinessField() {
        Id fakeId = TriggerTestUtility.getFakeId(Account.SObjectType);
        Account acc = new Account(Id = fakeId, Name = 'Test Account', Business__c = 'Some Business (America/New_York)');
        Account oldAcc = new Account(Id = fakeId, Name = 'Test Account');

        Test.startTest();
        new TA_Account_TzFromBusiness().beforeUpdate(new List<Account>{ acc }, new List<Account>{ oldAcc });
        Test.stopTest();

        System.assertEquals('America/New_York', acc.TimeZoneName__c, 'TimeZoneName__c should be parsed out of the parentheses in Business__c');
    }

    @isTest
    static void test_doesNothingWhenBusinessIsBlank() {
        Id fakeId = TriggerTestUtility.getFakeId(Account.SObjectType);
        Account acc = new Account(Id = fakeId, Name = 'Test Account');
        Account oldAcc = new Account(Id = fakeId, Name = 'Test Account');

        Test.startTest();
        new TA_Account_TzFromBusiness().beforeUpdate(new List<Account>{ acc }, new List<Account>{ oldAcc });
        Test.stopTest();

        System.assertEquals(null, acc.TimeZoneName__c, 'TimeZoneName__c should be untouched when Business__c is blank');
    }

    @isTest
    static void test_skipsRecordTypeForJpAccounts() {
        Map<String, Schema.RecordTypeInfo> rtByDeveloperName = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        if (!rtByDeveloperName.containsKey('JP_Accounts')) {
            return;
        }

        Id fakeId = TriggerTestUtility.getFakeId(Account.SObjectType);
        Id recordTypeId = rtByDeveloperName.get('JP_Accounts').getRecordTypeId();
        Account acc = new Account(Id = fakeId, Name = 'JP Account', RecordTypeId = recordTypeId, Business__c = 'Some Business (Asia/Tokyo)');
        Account oldAcc = new Account(Id = fakeId, Name = 'JP Account', RecordTypeId = recordTypeId);

        Test.startTest();
        new TA_Account_TzFromBusiness().beforeUpdate(new List<Account>{ acc }, new List<Account>{ oldAcc });
        Test.stopTest();

        System.assertEquals(null, acc.TimeZoneName__c, 'JP_Accounts record type should be excluded from this action');
    }
}
