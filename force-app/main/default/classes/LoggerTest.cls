/**
 * Unit tests for {@link Logger}. Each scenario drives one public entry point and asserts on the
 * `System_Log__c` rows produced once the async commit has run.
 */
@IsTest
private class LoggerTest {
    private class WidgetException extends Exception {
    }

    @IsTest
    static void startTransactionIsIdempotentAndTransactionIdIsStable() {
        Logger.startTransaction();
        String first = Logger.getTransactionId();
        Logger.startTransaction();
        String second = Logger.getTransactionId();

        System.assertEquals(first, second, 'Transaction id must be stable within a transaction');
        System.assert(first.startsWith(UserInfo.getUserId()), 'Transaction id should embed the running user id');
        System.assert(first.split('-').size() >= 3, 'Expected userId-millis-random shape');
    }

    private static void provokeException() {
        throw new WidgetException('boom from helper');
    }

    @IsTest
    static void logApexExceptionParsesStackAndPersists() {
        Test.startTest();
        try {
            provokeException(); // nested call guarantees a real multi-frame stack trace
        } catch (Exception e) {
            Logger.logApexException(e, 'Trigger', 'Account Automation', '001000000000000AAA', new Map<String, Object>{ 'attempt' => 1 });
        }
        System.assertEquals(1, Logger.getBufferSize(), 'Exception should be buffered, not committed');
        Logger.commitLogs();
        Test.stopTest();

        System_Log__c log = [
            SELECT Log_Type_Execution_Context__c, Log_Subtype__c, Module__c, Message__c, Stack_Trace__c, Class_Name__c,
                   Method_Name__c, Transaction_ID__c, Executing_User__c, Limits__c, Additional_Information__c,
                   Source_Record_ID__c, Execution_Time__c, Duration_ms__c
            FROM System_Log__c
            LIMIT 1
        ];
        System.assertEquals('Apex Exception', log.Log_Type_Execution_Context__c);
        System.assertEquals('Trigger', log.Log_Subtype__c);
        System.assertEquals('Account Automation', log.Module__c);
        System.assertEquals(UserInfo.getUserId(), log.Executing_User__c);
        System.assert(String.isNotBlank(log.Stack_Trace__c), 'Stack trace should be captured');
        System.assert(String.isNotBlank(log.Class_Name__c), 'Class name should be parsed from the stack trace');
        System.assert(log.Limits__c.contains('SOQL queries'), 'Limit snapshot should be present');
        System.assert(log.Additional_Information__c.contains('attempt'), 'Additional info should be serialized');
        System.assertNotEquals(null, log.Execution_Time__c);
        System.assertNotEquals(null, log.Duration_ms__c);
    }

    @IsTest
    static void logApexExceptionNullIsIgnored() {
        Logger.logApexException(null);
        System.assertEquals(0, Logger.getBufferSize());
    }

    @IsTest
    static void logFlowExceptionInvocableCommitsImmediately() {
        Logger.FlowLogRequest req = new Logger.FlowLogRequest();
        req.faultMessage = 'The flow failed to update the record.';
        req.flowApiName = 'Account_After_Save_Flow';
        req.logSubtype = 'Record Triggered Flow';
        req.sourceRecordId = '001000000000000AAA';
        req.module = 'Account Automation';

        Test.startTest();
        List<Logger.FlowLogResult> results = Logger.logFlowException(new List<Logger.FlowLogRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(String.isNotBlank(results[0].transactionId));

        System_Log__c log = [
            SELECT Log_Type_Execution_Context__c, Log_Subtype__c, Message__c, Class_Name__c, Module__c, Additional_Information__c
            FROM System_Log__c
            LIMIT 1
        ];
        System.assertEquals('Flow Exception', log.Log_Type_Execution_Context__c);
        System.assertEquals('Record Triggered Flow', log.Log_Subtype__c);
        System.assertEquals('The flow failed to update the record.', log.Message__c);
        System.assertEquals('Account_After_Save_Flow', log.Class_Name__c);
    }

    @IsTest
    static void logTransactionPrimitiveOverloadCommits() {
        Test.startTest();
        String txnId = Logger.logTransaction('Generic Transaction', 'LWC', 'User opened the pricing modal', '006000000000000AAA');
        Test.stopTest();

        System.assert(String.isNotBlank(txnId));
        System_Log__c log = [SELECT Log_Type_Execution_Context__c, Log_Subtype__c, Message__c, Source_Record_ID__c FROM System_Log__c LIMIT 1];
        System.assertEquals('Generic Transaction', log.Log_Type_Execution_Context__c);
        System.assertEquals('LWC', log.Log_Subtype__c);
        System.assertEquals('006000000000000AAA', log.Source_Record_ID__c);
    }

    @IsTest
    static void logTransactionDetailsStructuredOverloadCommits() {
        Logger.LogEntry entry = new Logger.LogEntry();
        entry.logType = 'UI Exception';
        entry.logSubtype = 'LWC';
        entry.message = 'TypeError: Cannot read properties of undefined';
        entry.stackTrace = 'at pricingTable.render (c/pricingTable.js:42)';
        entry.componentName = 'c/pricingTable';
        entry.methodName = 'render';
        entry.lineNumber = '42';
        entry.module = 'CPQ';
        entry.sourceRecordId = '006000000000000AAA';

        Test.startTest();
        String txnId = Logger.logTransactionDetails(entry);
        Test.stopTest();

        System.assert(String.isNotBlank(txnId));
        System_Log__c log = [
            SELECT Log_Type_Execution_Context__c, Class_Name__c, Method_Name__c, Line_Number__c, Module__c, Stack_Trace__c
            FROM System_Log__c
            LIMIT 1
        ];
        System.assertEquals('UI Exception', log.Log_Type_Execution_Context__c);
        System.assertEquals('c/pricingTable', log.Class_Name__c);
        System.assertEquals('render', log.Method_Name__c);
        System.assertEquals('42', log.Line_Number__c);
    }

    @IsTest
    static void logTransactionDetailsHandlesNullEntry() {
        Test.startTest();
        String txnId = Logger.logTransactionDetails(null);
        Test.stopTest();
        System.assert(String.isNotBlank(txnId));
        System.assertEquals(1, [SELECT COUNT() FROM System_Log__c]);
    }

    @IsTest
    static void logApiTransactionFromHttpObjects() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:My_Named_Cred/v1/quotes');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer super-secret');
        req.setHeader('X-Correlation-Id', 'abc-123');
        req.setBody('{"quoteId":"a1B000000000001"}');

        HttpResponse res = new HttpResponse();
        res.setStatusCode(201);
        res.setStatus('Created');
        res.setBody('{"id":"ext-999"}');

        Test.startTest();
        Logger.logApiTransaction(req, res, 350L, 'CPQ Integration', new List<String>{ 'Authorization', 'X-Correlation-Id' });
        System.assertEquals(1, Logger.getBufferSize());
        Logger.commitLogs();
        Test.stopTest();

        System_Log__c log = [
            SELECT Log_Type_Execution_Context__c, Endpoint__c, Method__c, Request_Body__c, Request_Headers__c, Response_Body__c,
                   Response_Status__c, Response_Status_Code__c, Additional_Information__c
            FROM System_Log__c
            LIMIT 1
        ];
        System.assertEquals('API Transaction', log.Log_Type_Execution_Context__c);
        System.assertEquals('POST', log.Method__c);
        System.assertEquals('201', log.Response_Status_Code__c);
        System.assertEquals('Created', log.Response_Status__c);
        System.assert(log.Request_Headers__c.contains('redacted'), 'Authorization header should be redacted');
        System.assert(log.Request_Headers__c.contains('abc-123'), 'Non-sensitive header should be kept');
        System.assert(log.Additional_Information__c.contains('calloutDurationMs'));
    }

    @IsTest
    static void logApiTransactionFromExplicitEntry() {
        Logger.ApiLogEntry entry = new Logger.ApiLogEntry();
        entry.endpoint = '/services/apexrest/inbound/orders';
        entry.method = 'PUT';
        entry.requestBody = '{"order":1}';
        entry.responseBody = '{"ok":true}';
        entry.responseStatus = 'OK';
        entry.responseStatusCode = '200';
        entry.durationMs = 12L;
        entry.module = 'Order Sync';

        Test.startTest();
        Logger.logApiTransaction(entry);
        Logger.commitLogs();
        Test.stopTest();

        System_Log__c log = [SELECT Method__c, Endpoint__c, Response_Status_Code__c, Module__c FROM System_Log__c LIMIT 1];
        System.assertEquals('PUT', log.Method__c);
        System.assertEquals('200', log.Response_Status_Code__c);
        System.assertEquals('Order Sync', log.Module__c);
    }

    @IsTest
    static void logUserActionBuffersAndBatchesWithOtherLogs() {
        Test.startTest();
        Logger.logUserAction('Clicked Recalculate Prices', 'Button Click', '006000000000000AAA');
        Logger.logUserAction('Uploaded 25 rows', 'Data Upsert', '006000000000000AAA', 'Data Loader', new Map<String, Object>{ 'rows' => 25 });
        System.assertEquals(2, Logger.getBufferSize());
        Logger.commitLogs();
        Test.stopTest();

        List<System_Log__c> logs = [SELECT Log_Type_Execution_Context__c, Log_Subtype__c, Transaction_ID__c FROM System_Log__c ORDER BY Log_Subtype__c];
        System.assertEquals(2, logs.size());
        System.assertEquals('User Action', logs[0].Log_Type_Execution_Context__c);
        System.assertEquals(logs[0].Transaction_ID__c, logs[1].Transaction_ID__c, 'Both logs share one transaction id');
    }

    @IsTest
    static void flushDiscardsBufferedLogs() {
        Logger.logUserAction('will be dropped', 'Button Click', null);
        System.assertEquals(1, Logger.getBufferSize());

        Test.startTest();
        Logger.flush();
        Logger.commitLogs();
        Test.stopTest();

        System.assertEquals(0, Logger.getBufferSize());
        System.assertEquals(0, [SELECT COUNT() FROM System_Log__c]);
    }

    @IsTest
    static void commitLogsIsNoOpWhenBufferEmpty() {
        Test.startTest();
        Logger.commitLogs();
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM System_Log__c]);
    }

    @IsTest
    static void commitLogsFallsBackToSyncInsertInAsyncContext() {
        // Exercise the future-context branch: enqueue not allowed, persist() runs inline.
        Test.startTest();
        enqueueFromFuture();
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM System_Log__c], 'Log should still be inserted synchronously from a future');
    }

    @future
    private static void enqueueFromFuture() {
        Logger.logUserAction('from future', 'Send Email', null);
        Logger.commitLogs();
    }

    @IsTest
    static void parseStackTraceHandlesCommonShapes() {
        System.assertEquals(
            'MyClass',
            Logger.parseStackTrace('Class.MyClass.doWork: line 12, column 1').className
        );
        System.assertEquals(
            'doWork',
            Logger.parseStackTrace('Class.MyClass.doWork: line 12, column 1').methodName
        );
        System.assertEquals(
            '12',
            Logger.parseStackTrace('Class.MyClass.doWork: line 12, column 1').lineNumber
        );
        System.assertEquals(
            'Trigger.AccountTrigger',
            Logger.parseStackTrace('Trigger.AccountTrigger: line 5, column 1').className
        );
        System.assertEquals(null, Logger.parseStackTrace(null).className);
    }

    @IsTest
    static void longValuesAreTruncatedToFieldLimits() {
        String hugeMessage = 'x'.repeat(140000);
        WidgetException ex = new WidgetException(hugeMessage);

        Test.startTest();
        Logger.logApexException(ex, 'Queueable Apex', 'Stress', null, null);
        Logger.commitLogs();
        Test.stopTest();

        System_Log__c log = [SELECT Message__c FROM System_Log__c LIMIT 1];
        System.assert(log.Message__c.length() <= 131072, 'Message must be clamped to the long text area ceiling');
    }
}