/**
 * Server-side broker for Amazon S3 access from the amazonS3* LWCs.
 *
 * AWS credentials never leave Apex. The browser receives only short-lived presigned URLs
 * (see S3Presigner) and moves file bytes directly to/from S3, so file size is not bound by
 * Apex heap or callout limits. Every method authorises the caller against the Salesforce
 * record before signing anything, and object keys are always derived/validated server side.
 *
 * Requires a Remote Site Setting for the bucket host(s) (used by listFiles / deleteFile).
 */
public with sharing class S3FilesHelper {

    @TestVisible static final Integer UPLOAD_URL_EXPIRY_SECONDS = 300;
    @TestVisible static final Integer DOWNLOAD_URL_EXPIRY_SECONDS = 60;
    static final Integer MAX_LIST_PAGES = 10; // 1000 keys per page
    static final String S3_NS = 'http://s3.amazonaws.com/doc/2006-03-01/';

    // ---------------------------------------------------------------------------------
    // DTOs
    // ---------------------------------------------------------------------------------

    public class S3File {
        @AuraEnabled public String key;
        @AuraEnabled public String name;
        @AuraEnabled public Long size;
        @AuraEnabled public String lastModified;
        @AuraEnabled public String etag;
    }

    public class UploadTicket {
        @AuraEnabled public String key;
        @AuraEnabled public String url;
        /** Headers the browser must send, with exactly these values, on the PUT. */
        @AuraEnabled public Map<String, String> headers;
    }

    // ---------------------------------------------------------------------------------
    // amazonS3Software / amazonS3Files / amazonS3LoadAndFetchDetails / amazonS3FetchDetails
    // ---------------------------------------------------------------------------------

    /** Lists the files stored under the record's prefix. Requires read access to the record. */
    @AuraEnabled
    public static List<S3File> listFiles(Id recordId) {
        requireReadAccess(recordId);
        return fetchS3Files(recordId);
    }

    /** Lists objects under the record's prefix via ListObjectsV2 (caller must authorise). */
    static List<S3File> fetchS3Files(Id recordId) {
        String prefix = prefixFor(recordId) + '/';

        List<S3File> files = new List<S3File>();
        String continuationToken;
        try {
            for (Integer page = 0; page < MAX_LIST_PAGES; page++) {
                Map<String, String> query = new Map<String, String>{
                    'list-type' => '2',
                    'prefix' => prefix
                };
                if (continuationToken != null) {
                    query.put('continuation-token', continuationToken);
                }
                HttpResponse res = send('GET', S3Presigner.presign('GET', '', 60, query));
                if (res.getStatusCode() != 200) {
                    throw new S3Presigner.S3Exception('S3 list failed: ' + res.getStatusCode() + ' ' + res.getBody());
                }

                Dom.XmlNode root = res.getBodyDocument().getRootElement();
                for (Dom.XmlNode node : root.getChildElements()) {
                    if (node.getName() != 'Contents') {
                        continue;
                    }
                    Long size = Long.valueOf(node.getChildElement('Size', S3_NS).getText());
                    if (size == 0) {
                        continue; // "folder" placeholder objects
                    }
                    S3File f = new S3File();
                    f.key = node.getChildElement('Key', S3_NS).getText();
                    f.name = f.key.substringAfterLast('/');
                    f.size = size;
                    f.lastModified = node.getChildElement('LastModified', S3_NS).getText();
                    Dom.XmlNode etagNode = node.getChildElement('ETag', S3_NS);
                    f.etag = etagNode == null ? null : etagNode.getText();
                    files.add(f);
                }

                Dom.XmlNode truncated = root.getChildElement('IsTruncated', S3_NS);
                Dom.XmlNode next = root.getChildElement('NextContinuationToken', S3_NS);
                if (truncated == null || truncated.getText() != 'true' || next == null) {
                    break;
                }
                continuationToken = next.getText();
            }
        } catch (Exception e) {
            throw auraError(e);
        }
        return files;
    }

    /**
     * Returns a presigned PUT URL for uploading a file under the record's prefix.
     * The browser PUTs the file body directly to S3. Requires edit access to the record.
     *
     * @param checksumCrc32 base64 CRC32 of the file body. Signed into the URL as the
     *        x-amz-checksum-crc32 header, so S3 only accepts that exact content. Required by S3
     *        for buckets with Object Lock; verifies upload integrity on all buckets.
     */
    @AuraEnabled
    public static UploadTicket getUploadUrl(Id recordId, String fileName, String checksumCrc32) {
        requireEditAccess(recordId);
        String safeName = sanitizeFileName(fileName);

        UploadTicket t = new UploadTicket();
        t.key = prefixFor(recordId) + '/' + safeName;
        t.headers = new Map<String, String>();
        if (String.isNotBlank(checksumCrc32)) {
            // CRC32 = 4 bytes => 8 base64 characters ending in '=='
            if (!Pattern.matches('[A-Za-z0-9+/]{6}==', checksumCrc32)) {
                throw new AuraHandledException('Invalid file checksum.');
            }
            t.headers.put('x-amz-checksum-crc32', checksumCrc32);
        }
        try {
            t.url = S3Presigner.presign('PUT', t.key, UPLOAD_URL_EXPIRY_SECONDS, null, t.headers);
        } catch (Exception e) {
            throw auraError(e);
        }
        return t;
    }

    /**
     * Returns a short-lived presigned GET URL for a file under the record's prefix.
     * @param asAttachment true forces a browser download, false lets the browser preview it
     */
    @AuraEnabled
    public static String getFileUrl(Id recordId, String key, Boolean asAttachment) {
        requireReadAccess(recordId);
        requireKeyBelongsToRecord(recordId, key);
        try {
            return S3Presigner.presign('GET', key, DOWNLOAD_URL_EXPIRY_SECONDS,
                dispositionParams(key, asAttachment == true));
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    /** Deletes a file under the record's prefix. Requires edit access to the record. */
    @AuraEnabled
    public static void deleteFile(Id recordId, String key) {
        requireEditAccess(recordId);
        requireKeyBelongsToRecord(recordId, key);
        try {
            HttpResponse res = send('DELETE', S3Presigner.presign('DELETE', key, 60, null));
            if (res.getStatusCode() != 204 && res.getStatusCode() != 200) {
                throw new S3Presigner.S3Exception('S3 delete failed: ' + res.getStatusCode() + ' ' + res.getBody());
            }
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    /**
     * Records an uploaded file on Software_File__c: updates recId when given, otherwise inserts
     * a new record. The key must sit under a record prefix the user can edit (the record the
     * file was uploaded against, as returned by getUploadUrl).
     */
    @AuraEnabled
    public static Id createSoftwareRecord(
        String fileName,
        String fileKey,
        Long fileSize,
        String etag,
        Id recId
    ) {
        Id ownerId = ownerIdFromKey(fileKey);
        requireEditAccess(ownerId);
        requireKeyBelongsToRecord(ownerId, fileKey);
        if (recId != null && recId != ownerId) {
            requireEditAccess(recId);
        }
        return saveSoftwareRecord(fileName, fileKey, fileSize, etag, Date.today(), recId);
    }

    /**
     * Reads the files stored under a Software_File__c's prefix from S3 and writes the details of
     * the most recently modified one (key, size, ETag, date) onto the record.
     * Returns the synced file, or null when no file exists in S3.
     */
    @AuraEnabled
    public static S3File syncFileDetails(Id recordId) {
        requireEditAccess(recordId);
        if (recordId.getSObjectType() != Software_File__c.SObjectType) {
            throw new AuraHandledException('File details can only be synced onto a Software File record.');
        }
        List<S3File> files;
        try {
            files = fetchS3Files(recordId); // callout must happen before the DML below
        } catch (Exception e) {
            throw auraError(e);
        }
        if (files.isEmpty()) {
            return null;
        }
        S3File latest = files[0];
        for (S3File f : files) {
            if (f.lastModified.compareTo(latest.lastModified) > 0) {
                latest = f;
            }
        }
        Date modified = String.isBlank(latest.lastModified)
            ? Date.today()
            : Date.valueOf(latest.lastModified.left(10));
        saveSoftwareRecord(latest.name, latest.key, latest.size, latest.etag, modified, recordId);
        return latest;
    }

    static Id saveSoftwareRecord(String fileName, String fileKey, Long fileSize, String etag, Date fileDate, Id recId) {
        Software_File__c softwareRecord = new Software_File__c(
            Id = recId,
            Name = fileName,
            File_Key__c = fileKey,
            Uploaded_File_URL__c = S3Presigner.objectUrl(fileKey),
            File_Description__c = 'File uploaded to AWS S3',
            Download_Available__c = true,
            Content_Detail__c = 'Size: ' + fileSize + ' bytes',
            File_Status__c = 'Loaded',
            File_ID__c = etag,
            Loaded_Date__c = fileDate,
            Last_Uploaded__c = fileDate,
            File_Size_bytes__c = fileSize
        );
        upsert softwareRecord;
        return softwareRecord.Id;
    }

    // ---------------------------------------------------------------------------------
    // amazonS3Download
    // ---------------------------------------------------------------------------------

    /**
     * Returns a presigned download URL for a Software_File__c, only if the current user is
     * entitled to it (same rules as getSoftwareFile). The key comes from the record, never
     * from the client.
     */
    @AuraEnabled
    public static String getDownloadUrl(Id recordId) {
        Software_File__c softwareFile = getSoftwareFile(recordId);
        if (softwareFile == null || String.isBlank(softwareFile.File_Key__c)) {
            throw new AuraHandledException('You are not entitled to download this file.');
        }
        try {
            return S3Presigner.presign('GET', softwareFile.File_Key__c, DOWNLOAD_URL_EXPIRY_SECONDS,
                dispositionParams(softwareFile.File_Key__c, true));
        } catch (Exception e) {
            throw auraError(e);
        }
    }

    @AuraEnabled(cacheable=true)
    public static Software_File__c getSoftwareFile(Id recordId) {
        try {
            Set<Id> catalogIdSet = new Set<Id>();

            List<User> loggedInUser = [SELECT Id, AccountId FROM User WHERE Id = :UserInfo.getUserId()];
            if (!loggedInUser.isEmpty()) {
                for (Entitle_Line_Item__c eachELI : [
                    SELECT Catalog_Item__c
                    FROM Entitle_Line_Item__c
                    WHERE Entitle_Account__r.Account__c = :loggedInUser[0].AccountId
                    LIMIT 5000
                ]) {
                    catalogIdSet.add(eachELI.Catalog_Item__c);
                }

                // Directly check if the recordId is associated through Software_File_Allocation__c
                List<Software_File_Allocation__c> relatedAllocations = [
                    SELECT Id
                    FROM Software_File_Allocation__c
                    WHERE Software__c = :recordId AND Firmware__c IN (
                        SELECT Firmware__c
                        FROM Catalog_Line_Item__c
                        WHERE Catalog_Item__c IN :catalogIdSet)
                    LIMIT 1
                ];

                if (relatedAllocations.size() > 0) {
                    return [
                        SELECT Id, File_Key__c
                        FROM Software_File__c
                        WHERE Id = :recordId
                        LIMIT 1
                    ];
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
        return null;
    }

    // ---------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------

    @TestVisible
    static String prefixFor(Id recordId) {
        return recordId.getSObjectType().getDescribe().getName() + '/' + recordId;
    }

    @TestVisible
    static String sanitizeFileName(String fileName) {
        if (String.isBlank(fileName)) {
            throw new AuraHandledException('File name is required.');
        }
        // No path separators or control characters - the key must stay inside the record prefix.
        String safe = fileName.replaceAll('[\\\\/\\p{Cntrl}]', '_').trim();
        if (safe == '.' || safe == '..' || String.isBlank(safe)) {
            throw new AuraHandledException('Invalid file name.');
        }
        return safe.left(255);
    }

    static Map<String, String> dispositionParams(String key, Boolean asAttachment) {
        String name = key.substringAfterLast('/');
        String asciiName = name.replaceAll('[^\\x20-\\x7E]', '_').replace('"', '_').replace('\\', '_');
        String disposition = (asAttachment ? 'attachment' : 'inline')
            + '; filename="' + asciiName + '"'
            + '; filename*=UTF-8\'\'' + S3Presigner.enc(name);
        return new Map<String, String>{ 'response-content-disposition' => disposition };
    }

    /** Keys are '<SObject>/<RecordId>/<file name>'; returns the record Id segment. */
    @TestVisible
    static Id ownerIdFromKey(String key) {
        List<String> parts = String.isBlank(key) ? new List<String>() : key.split('/');
        if (parts.size() < 3) {
            throw new AuraHandledException('Invalid file key.');
        }
        try {
            return Id.valueOf(parts[1]);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid file key.');
        }
    }

    static void requireKeyBelongsToRecord(Id recordId, String key) {
        if (String.isBlank(key) || !key.startsWith(prefixFor(recordId) + '/')) {
            throw new AuraHandledException('File does not belong to this record.');
        }
    }

    static void requireReadAccess(Id recordId) {
        if (!recordAccess(recordId).HasReadAccess) {
            throw new AuraHandledException('You do not have access to this record.');
        }
    }

    static void requireEditAccess(Id recordId) {
        if (!recordAccess(recordId).HasEditAccess) {
            throw new AuraHandledException('You do not have permission to modify files on this record.');
        }
    }

    static UserRecordAccess recordAccess(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }
        List<UserRecordAccess> rows = [
            SELECT RecordId, HasReadAccess, HasEditAccess
            FROM UserRecordAccess
            WHERE UserId = :UserInfo.getUserId() AND RecordId = :recordId
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('You do not have access to this record.');
        }
        return rows[0];
    }

    static HttpResponse send(String method, String url) {
        HttpRequest req = new HttpRequest();
        req.setMethod(method);
        req.setEndpoint(url);
        req.setTimeout(20000);
        return new Http().send(req);
    }

    static AuraHandledException auraError(Exception e) {
        if (e instanceof AuraHandledException) {
            return (AuraHandledException) e;
        }
        AuraHandledException ex = new AuraHandledException(e.getMessage());
        ex.setMessage(e.getMessage());
        return ex;
    }
}