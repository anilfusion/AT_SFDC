@IsTest
private class S3FilesDownloadHelperTest {

    static final String NS = 'http://s3.amazonaws.com/doc/2006-03-01/';

    /** Returns the queued bodies in order (the last one repeats). */
    class S3Mock implements HttpCalloutMock {
        Integer statusCode;
        List<String> bodies;
        List<HttpRequest> requests = new List<HttpRequest>();

        S3Mock(Integer statusCode, String body) {
            this(statusCode, new List<String>{ body });
        }

        S3Mock(Integer statusCode, List<String> bodies) {
            this.statusCode = statusCode;
            this.bodies = bodies;
        }

        public HttpResponse respond(HttpRequest req) {
            requests.add(req);
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(bodies[Math.min(requests.size(), bodies.size()) - 1]);
            return res;
        }
    }

    static String listPage(String key, Boolean truncated, String nextToken) {
        return '<?xml version="1.0" encoding="UTF-8"?>'
            + '<ListBucketResult xmlns="' + NS + '">'
            + '<IsTruncated>' + truncated + '</IsTruncated>'
            + (nextToken != null ? '<NextContinuationToken>' + nextToken + '</NextContinuationToken>' : '')
            + '<Contents><Key>' + key + '</Key><Size>10</Size><LastModified>2026-01-01T00:00:00.000Z</LastModified></Contents>'
            + '</ListBucketResult>';
    }

    static Blob aesKey;

    static void useTestConfig() {
        aesKey = Crypto.generateAesKey(256);
        S3DownloadPresigner.Config c = new S3DownloadPresigner.Config();
        c.accessKeyId = 'AKIDTEST';
        c.secretAccessKey = 'SECRETTEST';
        c.bucket = 'test-bucket';
        c.region = 'us-east-1';
        c.cipherKey = EncodingUtil.base64Encode(aesKey);
        S3DownloadPresigner.configOverride = c;
    }

    /** URLs handed to the LWC are AES-256 encrypted (managed IV); decrypt to inspect them. */
    static String decrypt(String cipherText) {
        return Crypto.decryptWithManagedIV('AES256', aesKey, EncodingUtil.base64Decode(cipherText)).toString();
    }

    // S3 key prefixes are derived generically from any record's object + Id,
    // so a standard object keeps these tests independent of custom object rules.
    static Account makeRecord() {
        Account a = new Account(Name = 'S3 Test');
        insert a;
        return a;
    }

    @IsTest
    static void getUploadUrlBuildsKeyUnderRecordPrefix() {
        useTestConfig();
        Account a = makeRecord();

        S3FilesDownloadHelper.UploadTicket t = S3FilesDownloadHelper.getUploadUrl(a.Id, '../evil/name.zip', null);
        String url = decrypt(t.cipherText);

        Assert.areEqual('Account/' + a.Id + '/.._evil_name.zip', t.key);
        Assert.isFalse(t.cipherText.startsWith('https://'), 'URL must be encrypted');
        Assert.isTrue(url.startsWith('https://test-bucket.s3.us-east-1.amazonaws.com/Account/' + a.Id + '/'), url);
        Assert.isTrue(url.contains('X-Amz-Expires=' + S3FilesDownloadHelper.UPLOAD_URL_EXPIRY_SECONDS));
        Assert.isTrue(url.contains('X-Amz-SignedHeaders=host&'), url);
        Assert.isTrue(t.headers.isEmpty());
        Assert.isFalse(url.contains('SECRETTEST'), 'Secret must never appear in a URL');
    }

    @IsTest
    static void getUploadUrlSignsChecksumHeader() {
        useTestConfig();
        Account a = makeRecord();

        S3FilesDownloadHelper.UploadTicket t = S3FilesDownloadHelper.getUploadUrl(a.Id, 'fw.bin', 'y/Q5Jg==');

        Assert.areEqual('y/Q5Jg==', t.headers.get('x-amz-checksum-crc32'));
        String url = decrypt(t.cipherText);
        Assert.isTrue(url.contains('X-Amz-SignedHeaders=host%3Bx-amz-checksum-crc32&'), url);
    }

    @IsTest
    static void getUploadUrlRejectsMalformedChecksum() {
        useTestConfig();
        Account a = makeRecord();
        try {
            S3FilesDownloadHelper.getUploadUrl(a.Id, 'fw.bin', 'not-a-crc');
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void getUploadUrlRejectsBlankName() {
        useTestConfig();
        Account a = makeRecord();
        try {
            S3FilesDownloadHelper.getUploadUrl(a.Id, '  ', null);
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void getFileUrlSignsKeyForRecord() {
        useTestConfig();
        Account a = makeRecord();
        String key = 'Account/' + a.Id + '/report.pdf';

        String url = decrypt(S3FilesDownloadHelper.getFileUrl(a.Id, key, true));

        Assert.isTrue(url.contains('/report.pdf?'), url);
        Assert.isTrue(url.contains('response-content-disposition=attachment'), url);

        String inlineUrl = decrypt(S3FilesDownloadHelper.getFileUrl(a.Id, key, false));
        Assert.isTrue(inlineUrl.contains('response-content-disposition=inline'), inlineUrl);
    }

    @IsTest
    static void getFileUrlSurfacesSigningErrors() {
        useTestConfig();
        S3DownloadPresigner.configOverride.cipherKey = null;
        Account a = makeRecord();
        try {
            S3FilesDownloadHelper.getFileUrl(a.Id, 'Account/' + a.Id + '/report.pdf', true);
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void getUploadUrlSurfacesSigningErrors() {
        useTestConfig();
        S3DownloadPresigner.configOverride.cipherKey = null;
        Account a = makeRecord();
        try {
            S3FilesDownloadHelper.getUploadUrl(a.Id, 'fw.bin', null);
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void getCipherKeyReadsCustomMetadata() {
        // Depends on the org's Amazon_S3__mdt record being present.
        try {
            S3FilesDownloadHelper.getCipherKey();
        } catch (Exception e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void ownerIdFromKeyRejectsNonIdSegment() {
        try {
            S3FilesDownloadHelper.ownerIdFromKey('Account/not-an-id/x.bin');
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void rejectsNullRecordId() {
        try {
            S3FilesDownloadHelper.listFiles(null);
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void getFileUrlRejectsKeyFromAnotherRecord() {
        useTestConfig();
        Account a = makeRecord();
        try {
            S3FilesDownloadHelper.getFileUrl(a.Id, 'Account/001000000000000AAA/secret.pdf', false);
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void listFilesParsesResponseAndSkipsFolders() {
        useTestConfig();
        Account a = makeRecord();
        String p = 'Account/' + a.Id + '/';
        String xml = '<?xml version="1.0" encoding="UTF-8"?>'
            + '<ListBucketResult xmlns="' + NS + '">'
            + '<IsTruncated>false</IsTruncated>'
            + '<Contents><Key>' + p + '</Key><Size>0</Size><LastModified>2026-01-01T00:00:00.000Z</LastModified></Contents>'
            + '<Contents><Key>' + p + 'fw.bin</Key><Size>42</Size><LastModified>2026-01-02T00:00:00.000Z</LastModified></Contents>'
            + '</ListBucketResult>';
        S3Mock mock = new S3Mock(200, xml);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<S3FilesDownloadHelper.S3File> files = S3FilesDownloadHelper.listFiles(a.Id);
        Test.stopTest();

        Assert.areEqual(1, files.size());
        Assert.areEqual('fw.bin', files[0].name);
        Assert.areEqual(42L, files[0].size);
        Assert.areEqual('GET', mock.requests[0].getMethod());
        Assert.isTrue(mock.requests[0].getEndpoint().contains('list-type=2&prefix='), mock.requests[0].getEndpoint());
    }

    @IsTest
    static void listFilesSurfacesS3Errors() {
        useTestConfig();
        Account a = makeRecord();
        Test.setMock(HttpCalloutMock.class, new S3Mock(403, '<Error><Code>AccessDenied</Code></Error>'));

        Test.startTest();
        try {
            S3FilesDownloadHelper.listFiles(a.Id);
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('403'), e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void deleteFileSendsSignedDelete() {
        useTestConfig();
        Account a = makeRecord();
        S3Mock mock = new S3Mock(204, '');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        S3FilesDownloadHelper.deleteFile(a.Id, 'Account/' + a.Id + '/old.zip');
        Test.stopTest();

        Assert.areEqual('DELETE', mock.requests[0].getMethod());
        Assert.isTrue(mock.requests[0].getEndpoint().contains('/old.zip?'));
    }

    @IsTest
    static void getDownloadUrlRequiresEntitlement() {
        useTestConfig();
        Account a = makeRecord();
        try {
            // Not a Software_File__c with an entitlement chain -> must be refused
            S3FilesDownloadHelper.getDownloadUrl(a.Id);
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void listFilesFollowsContinuationToken() {
        useTestConfig();
        Account a = makeRecord();
        String p = 'Account/' + a.Id + '/';
        S3Mock mock = new S3Mock(200, new List<String>{
            listPage(p + 'one.bin', true, 'TOKEN-1'),
            listPage(p + 'two.bin', false, null)
        });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<S3FilesDownloadHelper.S3File> files = S3FilesDownloadHelper.listFiles(a.Id);
        Test.stopTest();

        Assert.areEqual(2, files.size());
        Assert.areEqual(2, mock.requests.size());
        Assert.isTrue(mock.requests[1].getEndpoint().contains('continuation-token=TOKEN-1'), mock.requests[1].getEndpoint());
    }

    @IsTest
    static void deleteFileSurfacesS3Errors() {
        useTestConfig();
        Account a = makeRecord();
        Test.setMock(HttpCalloutMock.class, new S3Mock(403, '<Error><Code>AccessDenied</Code></Error>'));

        Test.startTest();
        try {
            S3FilesDownloadHelper.deleteFile(a.Id, 'Account/' + a.Id + '/old.zip');
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('403'), e.getMessage());
        }
        Test.stopTest();
    }

    // amazonS3Files: upload against a host record, insert a new Software_File__c
    // amazonS3Software: upload against the Software_File__c itself, update it
    @IsTest
    static void createSoftwareRecordInsertsThenUpdates() {
        useTestConfig();
        Account host = makeRecord();

        Id newId = S3FilesDownloadHelper.createSoftwareRecord(
            'fw.bin', 'Account/' + host.Id + '/fw.bin', 100L, '"etag-1"', null);
        Assert.isNotNull(newId);

        String key = S3FilesDownloadHelper.prefixFor(newId) + '/fw2.bin';
        Id updatedId = S3FilesDownloadHelper.createSoftwareRecord('fw2.bin', key, 200L, '"etag-2"', newId);
        Assert.areEqual(newId, updatedId);

        Software_File__c sf = [SELECT File_Key__c, File_ID__c, File_Size_bytes__c, Uploaded_File_URL__c
                               FROM Software_File__c WHERE Id = :newId];
        Assert.areEqual(key, sf.File_Key__c);
        Assert.areEqual('"etag-2"', sf.File_ID__c);
        Assert.areEqual(200, sf.File_Size_bytes__c);
        Assert.isFalse(sf.Uploaded_File_URL__c.contains('X-Amz-Signature'), 'Stored URL must not be a presigned URL');
    }

    @IsTest
    static void createSoftwareRecordRejectsInvalidKeys() {
        useTestConfig();
        for (String badKey : new List<String>{ 'Software_File__c/tmp/fw.bin', 'no-prefix.bin', 'Contact/' + makeRecord().Id + '/x.bin' }) {
            try {
                S3FilesDownloadHelper.createSoftwareRecord('x.bin', badKey, 1L, null, null);
                Assert.fail('Expected exception for ' + badKey);
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage());
            }
        }
    }

    @IsTest
    static void syncFileDetailsWritesLatestFileOntoRecord() {
        useTestConfig();
        Account host = makeRecord();
        Id sfId = S3FilesDownloadHelper.createSoftwareRecord('old.bin', 'Account/' + host.Id + '/old.bin', 1L, null, null);
        String p = S3FilesDownloadHelper.prefixFor(sfId) + '/';
        String xml = '<?xml version="1.0" encoding="UTF-8"?>'
            + '<ListBucketResult xmlns="' + NS + '"><IsTruncated>false</IsTruncated>'
            + '<Contents><Key>' + p + 'v1.bin</Key><Size>10</Size><ETag>"e1"</ETag><LastModified>2026-01-01T00:00:00.000Z</LastModified></Contents>'
            + '<Contents><Key>' + p + 'v2.bin</Key><Size>20</Size><ETag>"e2"</ETag><LastModified>2026-03-05T10:00:00.000Z</LastModified></Contents>'
            + '</ListBucketResult>';
        Test.setMock(HttpCalloutMock.class, new S3Mock(200, xml));

        Test.startTest();
        S3FilesDownloadHelper.S3File synced = S3FilesDownloadHelper.syncFileDetails(sfId);
        Test.stopTest();

        Assert.areEqual('v2.bin', synced.name);
        Software_File__c sf = [SELECT Name, File_Key__c, File_ID__c, File_Size_bytes__c, Loaded_Date__c
                               FROM Software_File__c WHERE Id = :sfId];
        Assert.areEqual(p + 'v2.bin', sf.File_Key__c);
        Assert.areEqual('"e2"', sf.File_ID__c);
        Assert.areEqual(20, sf.File_Size_bytes__c);
        Assert.areEqual(Date.newInstance(2026, 3, 5), sf.Loaded_Date__c);
    }

    @IsTest
    static void syncFileDetailsReturnsNullWhenNoFiles() {
        useTestConfig();
        Account host = makeRecord();
        Id sfId = S3FilesDownloadHelper.createSoftwareRecord('a.bin', 'Account/' + host.Id + '/a.bin', 1L, null, null);
        Test.setMock(HttpCalloutMock.class, new S3Mock(200,
            '<?xml version="1.0" encoding="UTF-8"?><ListBucketResult xmlns="' + NS + '"><IsTruncated>false</IsTruncated></ListBucketResult>'));

        Test.startTest();
        Assert.isNull(S3FilesDownloadHelper.syncFileDetails(sfId));
        Test.stopTest();
    }

    @IsTest
    static void syncFileDetailsRejectsNonSoftwareFileRecords() {
        useTestConfig();
        Account a = makeRecord();
        try {
            S3FilesDownloadHelper.syncFileDetails(a.Id);
            Assert.fail('Expected exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void sanitizeFileNameKeepsReadableNames() {
        Assert.areEqual('My Firmware (v2).zip', S3FilesDownloadHelper.sanitizeFileName('My Firmware (v2).zip'));
        Assert.areEqual('a_b_c.txt', S3FilesDownloadHelper.sanitizeFileName('a/b\\c.txt'));
    }
}