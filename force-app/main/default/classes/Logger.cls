/**
 * ─────────────────────────────────────────────────────────────────────────────────────────────────┐
 * Logger
 *
 * Central entry point for the System Log framework. Every `log*` method builds a `System_Log__c`
 * record in a static in-memory buffer that lives for the duration of the current execution context.
 * Call `Logger.commitLogs()` once, at the end of the transaction, to persist the buffer via
 * `LoggerQueueable`. The Flow-invocable method and the `@AuraEnabled` methods call `commitLogs()`
 * for you, because they are themselves transaction entry points.
 *
 * Typical Apex usage:
 * ┌───────────────────────────────────────────────────────────────────────────────────────────────┐
 * │  Logger.startTransaction();                                                                    │
 * │  try {                                                                                         │
 * │      // ... work ...                                                                           │
 * │  } catch (Exception e) {                                                                       │
 * │      Logger.logApexException(e, 'Trigger', 'Account Automation', accountId);                   │
 * │      throw e;                                                                                  │
 * │  } finally {                                                                                   │
 * │      Logger.commitLogs();                                                                      │
 * │  }                                                                                             │
 * └───────────────────────────────────────────────────────────────────────────────────────────────┘
 * ─────────────────────────────────────────────────────────────────────────────────────────────────
 * @author            AT_Salesforce
 * @systemLayer       Apex Class
 * ─────────────────────────────────────────────────────────────────────────────────────────────────┘
 */
public without sharing class Logger {
    // ─────────────────────────────────────────────────────────────────────────────
    // Log Type (Execution Context) constants
    // ─────────────────────────────────────────────────────────────────────────────
    public static final String TYPE_APEX_EXCEPTION = 'Apex Exception';
    public static final String TYPE_FLOW_EXCEPTION = 'Flow Exception';
    public static final String TYPE_UI_EXCEPTION = 'UI Exception';
    public static final String TYPE_API_TRANSACTION = 'API Transaction';
    public static final String TYPE_GENERIC_TRANSACTION = 'Generic Transaction';
    public static final String TYPE_USER_ACTION = 'User Action';
    public static final String TYPE_STREAMING_API = 'Streaming API';

    // ─────────────────────────────────────────────────────────────────────────────
    // Field length ceilings (mirror the System_Log__c field metadata)
    // ─────────────────────────────────────────────────────────────────────────────
    private static final Integer TEXT_MAX = 255;
    private static final Integer LONG_TEXT_MAX = 131072;

    // ─────────────────────────────────────────────────────────────────────────────
    // Static transaction state
    // ─────────────────────────────────────────────────────────────────────────────
    @TestVisible
    private static final List<System_Log__c> BUFFER = new List<System_Log__c>();
    private static String transactionId;
    private static Long transactionStartMs;
    private static String cachedIpAddress;
    private static Boolean ipResolved = false;

    // ═════════════════════════════════════════════════════════════════════════════
    // Transaction helpers
    // ═════════════════════════════════════════════════════════════════════════════

    /**
     * Marks the start of the logical transaction so that `Duration (ms)` can be calculated
     * for every log entry written afterwards. Safe to call more than once - the first call wins.
     */
    public static void startTransaction() {
        if (transactionStartMs == null) {
            transactionStartMs = System.currentTimeMillis();
        }
    }

    /**
     * Returns (generating on first access) the correlation id shared by every log written
     * during this execution context. Format: {UserId}-{epochMillis}-{randomInt}.
     */
    public static String getTransactionId() {
        if (String.isBlank(transactionId)) {
            transactionId =
                UserInfo.getUserId() +
                '-' +
                String.valueOf(System.currentTimeMillis()) +
                '-' +
                String.valueOf(Math.abs(Crypto.getRandomInteger()));
        }
        return transactionId;
    }

    /** Number of buffered-but-not-yet-committed log records. */
    public static Integer getBufferSize() {
        return BUFFER.size();
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // 1. Log Flow Exception (Invocable)
    // ═════════════════════════════════════════════════════════════════════════════

    /**
     * Invocable entry point for Flow fault paths. Add this action to the fault connector of a
     * screen flow / record-triggered flow and pass the {!$Flow.FaultMessage}. Buffers one log
     * per request and commits immediately.
     */
    @InvocableMethod(label='Log Flow Exception' category='Logging' description='Writes a System Log entry for a Flow fault path.')
    public static List<FlowLogResult> logFlowException(List<FlowLogRequest> requests) {
        startTransaction();
        List<FlowLogResult> results = new List<FlowLogResult>();

        for (FlowLogRequest req : requests) {
            String subtype = String.isBlank(req.logSubtype) ? 'Screen Flow' : req.logSubtype;
            System_Log__c log = newLog(TYPE_FLOW_EXCEPTION, subtype);
            log.Source_Record_ID__c = truncate(req.sourceRecordId, 18);
            log.Module__c = truncate(req.module, TEXT_MAX);
            log.Message__c = truncate(
                coalesce(req.faultMessage, req.errorMessage, 'Unspecified Flow fault'),
                LONG_TEXT_MAX
            );
            log.Class_Name__c = truncate(coalesce(req.flowApiName, req.flowLabel), TEXT_MAX);
            log.Additional_Information__c = truncate(
                buildAdditionalInfo(
                    new Map<String, Object>{
                        'flowApiName' => req.flowApiName,
                        'flowLabel' => req.flowLabel,
                        'interviewGuid' => req.interviewGuid,
                        'notes' => req.additionalInformation
                    }
                ),
                LONG_TEXT_MAX
            );

            BUFFER.add(log);
            FlowLogResult result = new FlowLogResult();
            result.transactionId = log.Transaction_ID__c;
            results.add(result);
        }

        commitLogs();
        return results;
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // 2. Log Apex Exception
    // ═════════════════════════════════════════════════════════════════════════════

    /** Convenience overload - logs an Apex exception with no extra context. */
    public static void logApexException(Exception ex) {
        logApexException(ex, null, null, null, null);
    }

    /**
     * Buffers a `System_Log__c` for a caught Apex exception. The class name, method name and line
     * number are parsed from the exception's stack trace; a governor-limit snapshot is attached.
     * Does NOT commit - call `Logger.commitLogs()` in a finally block.
     *
     * @param ex               the caught exception (required)
     * @param logSubtype       System_Log__c.Log_Subtype__c value, e.g. 'Trigger', 'Batch Apex'
     * @param module           logical feature/module name
     * @param sourceRecordId   context record id, if any
     * @param additionalInfo   any extra key/value context to serialize into Additional Information
     */
    public static void logApexException(
        Exception ex,
        String logSubtype,
        String module,
        String sourceRecordId,
        Map<String, Object> additionalInfo
    ) {
        if (ex == null) {
            return;
        }
        startTransaction();

        System_Log__c log = newLog(TYPE_APEX_EXCEPTION, logSubtype);
        log.Source_Record_ID__c = truncate(sourceRecordId, 18);
        log.Module__c = truncate(module, TEXT_MAX);
        applyExceptionDetails(log, ex);
        if (additionalInfo != null && !additionalInfo.isEmpty()) {
            log.Additional_Information__c = truncate(buildAdditionalInfo(additionalInfo), LONG_TEXT_MAX);
        }

        BUFFER.add(log);
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // 3.1 Log Transaction (Aura Enabled) - primitive arguments
    // ═════════════════════════════════════════════════════════════════════════════

    /**
     * Lightweight `@AuraEnabled` entry point for LWC/Aura. Records a generic transaction / UI event
     * and commits immediately (the Apex call is its own transaction).
     *
     * @param logType         Log_Type_Execution_Context__c value (defaults to 'Generic Transaction' when blank)
     * @param logSubtype      Log_Subtype__c value, e.g. 'LWC', 'Aura'
     * @param message         human-readable description of what happened
     * @param sourceRecordId  context record id
     * @return the generated Transaction ID
     */
    @AuraEnabled
    public static String logTransaction(String logType, String logSubtype, String message, String sourceRecordId) {
        startTransaction();
        System_Log__c log = newLog(
            String.isBlank(logType) ? TYPE_GENERIC_TRANSACTION : logType,
            String.isBlank(logSubtype) ? 'LWC' : logSubtype
        );
        log.Message__c = truncate(message, LONG_TEXT_MAX);
        log.Source_Record_ID__c = truncate(sourceRecordId, 18);
        BUFFER.add(log);
        commitLogs();
        return log.Transaction_ID__c;
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // 3.2 Log Transaction (Aura Enabled) - structured payload (LWC error objects)
    // ═════════════════════════════════════════════════════════════════════════════

    /**
     * Rich `@AuraEnabled` entry point. Pass a `Logger.LogEntry` (works directly from LWC as a plain
     * object) carrying a caught JS error, component name, stack, etc. Commits immediately.
     *
     * @param entry the structured log payload
     * @return the generated Transaction ID
     */
    @AuraEnabled
    public static String logTransactionDetails(LogEntry entry) {
        startTransaction();
        if (entry == null) {
            entry = new LogEntry();
        }

        System_Log__c log = newLog(
            String.isBlank(entry.logType) ? TYPE_UI_EXCEPTION : entry.logType,
            String.isBlank(entry.logSubtype) ? 'LWC' : entry.logSubtype
        );
        log.Message__c = truncate(entry.message, LONG_TEXT_MAX);
        log.Stack_Trace__c = truncate(entry.stackTrace, LONG_TEXT_MAX);
        log.Class_Name__c = truncate(coalesce(entry.componentName, entry.className), TEXT_MAX);
        log.Method_Name__c = truncate(entry.methodName, TEXT_MAX);
        log.Line_Number__c = truncate(entry.lineNumber, TEXT_MAX);
        log.Module__c = truncate(entry.module, TEXT_MAX);
        log.Source_Record_ID__c = truncate(entry.sourceRecordId, 18);
        if (String.isNotBlank(entry.additionalInformation)) {
            log.Additional_Information__c = truncate(entry.additionalInformation, LONG_TEXT_MAX);
        }

        BUFFER.add(log);
        commitLogs();
        return log.Transaction_ID__c;
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // 4. Log API Transaction
    // ═════════════════════════════════════════════════════════════════════════════

    /**
     * Buffers a `System_Log__c` for an outbound callout from the standard `HttpRequest` /
     * `HttpResponse` objects. Request headers cannot be enumerated from `HttpRequest`, so pass
     * any header keys you care about in `requestHeaderKeys`. Does NOT commit.
     *
     * @param request           the HttpRequest that was sent (may be null)
     * @param response          the HttpResponse that was received (may be null)
     * @param durationMs        callout duration in milliseconds (may be null)
     * @param module            logical feature/module name
     * @param requestHeaderKeys header keys to read back off the request for logging (may be null)
     */
    public static void logApiTransaction(
        HttpRequest request,
        HttpResponse response,
        Long durationMs,
        String module,
        List<String> requestHeaderKeys
    ) {
        startTransaction();
        System_Log__c log = newLog(TYPE_API_TRANSACTION, 'Apex Controller');
        log.Module__c = truncate(module, TEXT_MAX);

        if (request != null) {
            log.Endpoint__c = truncate(safeEndpoint(request), TEXT_MAX);
            log.Method__c = truncate(request.getMethod(), TEXT_MAX);
            log.Request_Body__c = truncate(safeRequestBody(request), LONG_TEXT_MAX);
            log.Request_Headers__c = truncate(readRequestHeaders(request, requestHeaderKeys), TEXT_MAX);
        }

        if (response != null) {
            log.Response_Body__c = truncate(safeResponseBody(response), LONG_TEXT_MAX);
            log.Response_Status__c = truncate(response.getStatus(), TEXT_MAX);
            log.Response_Status_Code__c = String.valueOf(response.getStatusCode());
        }

        if (durationMs != null) {
            log.Additional_Information__c = truncate(
                buildAdditionalInfo(new Map<String, Object>{ 'calloutDurationMs' => durationMs }),
                LONG_TEXT_MAX
            );
        }

        BUFFER.add(log);
    }

    /**
     * Buffers a `System_Log__c` for an API transaction from explicit values - use this for inbound
     * REST/Apex web-service calls or when you already have the raw strings. Does NOT commit.
     */
    public static void logApiTransaction(ApiLogEntry entry) {
        startTransaction();
        if (entry == null) {
            entry = new ApiLogEntry();
        }

        System_Log__c log = newLog(
            TYPE_API_TRANSACTION,
            String.isBlank(entry.logSubtype) ? 'Apex Controller' : entry.logSubtype
        );
        log.Module__c = truncate(entry.module, TEXT_MAX);
        log.Source_Record_ID__c = truncate(entry.sourceRecordId, 18);
        log.Endpoint__c = truncate(entry.endpoint, TEXT_MAX);
        log.Method__c = truncate(entry.method, TEXT_MAX);
        log.Request_Body__c = truncate(entry.requestBody, LONG_TEXT_MAX);
        log.Request_Headers__c = truncate(entry.requestHeaders, TEXT_MAX);
        log.Response_Body__c = truncate(entry.responseBody, LONG_TEXT_MAX);
        log.Response_Status__c = truncate(entry.responseStatus, TEXT_MAX);
        log.Response_Status_Code__c = truncate(entry.responseStatusCode, TEXT_MAX);
        log.Message__c = truncate(entry.message, LONG_TEXT_MAX);
        if (entry.durationMs != null) {
            log.Additional_Information__c = truncate(
                buildAdditionalInfo(new Map<String, Object>{ 'apiDurationMs' => entry.durationMs, 'notes' => entry.additionalInformation }),
                LONG_TEXT_MAX
            );
        } else if (String.isNotBlank(entry.additionalInformation)) {
            log.Additional_Information__c = truncate(entry.additionalInformation, LONG_TEXT_MAX);
        }

        BUFFER.add(log);
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // 5. Log User Action
    // ═════════════════════════════════════════════════════════════════════════════

    /** Convenience overload. */
    public static void logUserAction(String action, String logSubtype, String sourceRecordId) {
        logUserAction(action, logSubtype, sourceRecordId, null, null);
    }

    /**
     * Buffers a `System_Log__c` describing something a user did - a button click, a data upsert,
     * a login, an email send, etc. Does NOT commit (call `commitLogs()`), so it can be batched
     * with other logs from the same transaction.
     *
     * @param action          description of the action ("Clicked Recalculate Prices")
     * @param logSubtype      Log_Subtype__c value, e.g. 'Button Click', 'Data Upsert', 'Login'
     * @param sourceRecordId  context record id
     * @param module          logical feature/module name
     * @param details         extra key/value context serialized into Additional Information
     */
    public static void logUserAction(
        String action,
        String logSubtype,
        String sourceRecordId,
        String module,
        Map<String, Object> details
    ) {
        startTransaction();
        System_Log__c log = newLog(TYPE_USER_ACTION, String.isBlank(logSubtype) ? 'Button Click' : logSubtype);
        log.Message__c = truncate(action, LONG_TEXT_MAX);
        log.Source_Record_ID__c = truncate(sourceRecordId, 18);
        log.Module__c = truncate(module, TEXT_MAX);
        if (details != null && !details.isEmpty()) {
            log.Additional_Information__c = truncate(buildAdditionalInfo(details), LONG_TEXT_MAX);
        }
        BUFFER.add(log);
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // 6. Flush / Clear
    // ═════════════════════════════════════════════════════════════════════════════

    /**
     * Discards every buffered log and resets the transaction timer / id. Use when you want to
     * abandon the logs collected so far without persisting them.
     */
    public static void flush() {
        BUFFER.clear();
        transactionStartMs = null;
        transactionId = null;
    }

    /** Alias for {@link #flush}. */
    public static void clear() {
        flush();
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // 7. Commit Logs
    // ═════════════════════════════════════════════════════════════════════════════

    /**
     * Persists every buffered log. The buffer is drained first, then handed to `LoggerQueueable`
     * so the DML never lands in the caller's transaction. When a queueable cannot be enqueued
     * (future context, or the per-transaction queueable ceiling is reached) the logs are inserted
     * synchronously as a fallback. Never throws.
     */
    public static void commitLogs() {
        if (BUFFER.isEmpty()) {
            return;
        }

        List<System_Log__c> toPersist = BUFFER.clone();
        // Backfill the final duration now that the transaction is ending.
        Long duration = transactionStartMs == null ? null : (System.currentTimeMillis() - transactionStartMs);
        if (duration != null) {
            for (System_Log__c log : toPersist) {
                if (log.Duration_ms__c == null) {
                    log.Duration_ms__c = duration;
                }
            }
        }

        flush();

        try {
            if (!System.isFuture() && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                System.enqueueJob(new LoggerQueueable(toPersist));
            } else {
                LoggerQueueable.persist(toPersist);
            }
        } catch (Exception e) {
            // Last resort: never let logging break the caller.
            try {
                LoggerQueueable.persist(toPersist);
            } catch (Exception fallbackError) {
                System.debug(LoggingLevel.ERROR, 'Logger.commitLogs failed to persist ' + toPersist.size() + ' logs: ' + fallbackError.getMessage());
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // Internal builders
    // ═════════════════════════════════════════════════════════════════════════════

    /** Creates a log pre-populated with the fields common to every entry. */
    private static System_Log__c newLog(String logType, String logSubtype) {
        startTransaction();
        Long duration = transactionStartMs == null ? null : (System.currentTimeMillis() - transactionStartMs);
        return new System_Log__c(
            Transaction_ID__c = truncate(getTransactionId(), TEXT_MAX),
            Executing_User__c = UserInfo.getUserId(),
            IP_Address__c = truncate(resolveIpAddress(), TEXT_MAX),
            Execution_Time__c = System.now(),
            Duration_ms__c = duration,
            Log_Type_Execution_Context__c = logType,
            Log_Subtype__c = logSubtype,
            Limits__c = truncate(captureLimits(), LONG_TEXT_MAX)
        );
    }

    private static void applyExceptionDetails(System_Log__c log, Exception ex) {
        log.Message__c = truncate(ex.getTypeName() + ': ' + ex.getMessage(), LONG_TEXT_MAX);
        String stackTrace = ex.getStackTraceString();
        log.Stack_Trace__c = truncate(stackTrace, LONG_TEXT_MAX);

        StackFrame frame = parseStackTrace(stackTrace);
        log.Class_Name__c = truncate(frame.className, TEXT_MAX);
        log.Method_Name__c = truncate(frame.methodName, TEXT_MAX);
        log.Line_Number__c = truncate(frame.lineNumber, TEXT_MAX);

        if (ex.getCause() != null) {
            log.Additional_Information__c = truncate(
                'Caused by: ' + ex.getCause().getTypeName() + ': ' + ex.getCause().getMessage(),
                LONG_TEXT_MAX
            );
        }
    }

    /**
     * Extracts class / method / line from the first frame of an Apex stack trace string.
     * Handles "Class.Foo.bar: line 12, column 1", "Trigger.Foo: line 3, column 1" and
     * "AnonymousBlock: line 1, column 1".
     */
    @TestVisible
    private static StackFrame parseStackTrace(String stackTraceString) {
        StackFrame frame = new StackFrame();
        if (String.isBlank(stackTraceString)) {
            return frame;
        }

        String firstLine = stackTraceString.split('\n')[0].trim();

        Matcher lineMatcher = Pattern.compile('line (\\d+)').matcher(firstLine);
        if (lineMatcher.find()) {
            frame.lineNumber = lineMatcher.group(1);
        }

        String locator = firstLine.contains(':') ? firstLine.substringBefore(':').trim() : firstLine;
        if (locator.startsWith('Class.')) {
            locator = locator.substringAfter('Class.');
        }

        if (locator.contains('.')) {
            frame.methodName = locator.substringAfterLast('.');
            frame.className = locator.substringBeforeLast('.');
        } else {
            frame.className = locator;
        }
        return frame;
    }

    /** Builds the governor-limit snapshot stored on every log. */
    @TestVisible
    private static String captureLimits() {
        return String.join(
            new List<String>{
                'SOQL queries: ' + Limits.getQueries() + ' / ' + Limits.getLimitQueries(),
                'Query rows: ' + Limits.getQueryRows() + ' / ' + Limits.getLimitQueryRows(),
                'DML statements: ' + Limits.getDmlStatements() + ' / ' + Limits.getLimitDmlStatements(),
                'DML rows: ' + Limits.getDmlRows() + ' / ' + Limits.getLimitDmlRows(),
                'CPU time (ms): ' + Limits.getCpuTime() + ' / ' + Limits.getLimitCpuTime(),
                'Heap size: ' + Limits.getHeapSize() + ' / ' + Limits.getLimitHeapSize(),
                'Callouts: ' + Limits.getCallouts() + ' / ' + Limits.getLimitCallouts(),
                'Queueable jobs: ' + Limits.getQueueableJobs() + ' / ' + Limits.getLimitQueueableJobs(),
                'Future calls: ' + Limits.getFutureCalls() + ' / ' + Limits.getLimitFutureCalls(),
                'Email invocations: ' + Limits.getEmailInvocations() + ' / ' + Limits.getLimitEmailInvocations()
            },
            '\n'
        );
    }

    /** Resolves the running user's source IP once per transaction; null in async / unavailable contexts. */
    @TestVisible
    private static String resolveIpAddress() {
        if (ipResolved) {
            return cachedIpAddress;
        }
        ipResolved = true;
        // Contexts with no interactive session: async Apex, and test runs. Calling
        // Auth.SessionManagement.getCurrentSession() from any of these throws
        // System.UnexpectedException ('Current session unavailable'), which is not always
        // catchable - so never reach it here.
        if (
            System.isBatch() ||
            System.isFuture() ||
            System.isQueueable() ||
            System.isScheduled() ||
            Test.isRunningTest()
        ) {
            return null;
        }
        // Automated Process / platform-event / record-triggered-flow contexts also run without a
        // session; getSessionId() is blank there and getCurrentSession() would throw.
        if (String.isBlank(UserInfo.getSessionId())) {
            return null;
        }
        try {
            Map<String, String> session = Auth.SessionManagement.getCurrentSession();
            if (session != null) {
                cachedIpAddress = session.get('SourceIp');
            }
        } catch (Exception ignored) {
            cachedIpAddress = null;
        }
        return cachedIpAddress;
    }

    private static String buildAdditionalInfo(Map<String, Object> data) {
        Map<String, Object> cleaned = new Map<String, Object>();
        for (String key : data.keySet()) {
            Object value = data.get(key);
            if (value != null && String.valueOf(value) != '') {
                cleaned.put(key, value);
            }
        }
        return cleaned.isEmpty() ? null : JSON.serializePretty(cleaned);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // HttpRequest / HttpResponse safe accessors
    // ─────────────────────────────────────────────────────────────────────────────

    private static String safeEndpoint(HttpRequest request) {
        try {
            return request.getEndpoint();
        } catch (Exception e) {
            return null;
        }
    }

    private static String safeRequestBody(HttpRequest request) {
        try {
            return request.getBody();
        } catch (Exception e) {
            return null;
        }
    }

    private static String safeResponseBody(HttpResponse response) {
        try {
            return response.getBody();
        } catch (Exception e) {
            return null;
        }
    }

    private static String readRequestHeaders(HttpRequest request, List<String> keys) {
        if (keys == null || keys.isEmpty()) {
            return null;
        }
        Map<String, String> headers = new Map<String, String>();
        for (String key : keys) {
            try {
                String value = request.getHeader(key);
                if (String.isNotBlank(value)) {
                    headers.put(key, maskSensitiveHeader(key, value));
                }
            } catch (Exception ignored) {
                // header not present
            }
        }
        return headers.isEmpty() ? null : JSON.serialize(headers);
    }

    private static String maskSensitiveHeader(String key, String value) {
        String lowered = key.toLowerCase();
        if (lowered == 'authorization' || lowered.contains('token') || lowered.contains('secret') || lowered.contains('api-key')) {
            return '***redacted***';
        }
        return value;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Generic helpers
    // ─────────────────────────────────────────────────────────────────────────────

    private static String truncate(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }

    private static String coalesce(String a, String b) {
        return String.isNotBlank(a) ? a : b;
    }

    private static String coalesce(String a, String b, String c) {
        if (String.isNotBlank(a)) {
            return a;
        }
        return String.isNotBlank(b) ? b : c;
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // DTOs
    // ═════════════════════════════════════════════════════════════════════════════

    /** Parsed origin frame of an Apex stack trace. */
    public class StackFrame {
        public String className;
        public String methodName;
        public String lineNumber;
    }

    /** Invocable input for {@link #logFlowException}. */
    public class FlowLogRequest {
        @InvocableVariable(label='Fault Message' description='Typically {!$Flow.FaultMessage}')
        public String faultMessage;

        @InvocableVariable(label='Error Message' description='Alternate/explicit error message')
        public String errorMessage;

        @InvocableVariable(label='Flow API Name')
        public String flowApiName;

        @InvocableVariable(label='Flow Label')
        public String flowLabel;

        @InvocableVariable(label='Log Subtype' description='Screen Flow / Record Triggered Flow / Platform Event')
        public String logSubtype;

        @InvocableVariable(label='Source Record Id')
        public String sourceRecordId;

        @InvocableVariable(label='Module')
        public String module;

        @InvocableVariable(label='Interview GUID')
        public String interviewGuid;

        @InvocableVariable(label='Additional Information')
        public String additionalInformation;
    }

    /** Invocable output for {@link #logFlowException}. */
    public class FlowLogResult {
        @InvocableVariable(label='Transaction Id')
        public String transactionId;
    }

    /** Structured payload for {@link #logTransactionDetails}. Usable as a plain object from LWC. */
    public class LogEntry {
        @AuraEnabled
        public String logType;
        @AuraEnabled
        public String logSubtype;
        @AuraEnabled
        public String message;
        @AuraEnabled
        public String stackTrace;
        @AuraEnabled
        public String componentName;
        @AuraEnabled
        public String className;
        @AuraEnabled
        public String methodName;
        @AuraEnabled
        public String lineNumber;
        @AuraEnabled
        public String module;
        @AuraEnabled
        public String sourceRecordId;
        @AuraEnabled
        public String additionalInformation;
    }

    /** Explicit-value payload for {@link #logApiTransaction(ApiLogEntry)}. */
    public class ApiLogEntry {
        public String logSubtype;
        public String module;
        public String sourceRecordId;
        public String endpoint;
        public String method;
        public String requestBody;
        public String requestHeaders;
        public String responseBody;
        public String responseStatus;
        public String responseStatusCode;
        public String message;
        public String additionalInformation;
        public Long durationMs;
    }
}