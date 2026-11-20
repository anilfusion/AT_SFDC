/**
 * Generates AWS Signature V4 presigned URLs for S3.
 *
 * The AWS credentials are read here, server side, and never leave Apex. Callers
 * (LWC via S3FilesDownloadHelper, or Apex callouts) only ever receive a short-lived URL
 * that grants a single operation on a single object.
 *
 * Signing is pure computation (HMAC-SHA256) - no callout - so it is not subject to
 * callout size limits; the file bytes go directly from the browser to S3.
 */
public inherited sharing class S3DownloadPresigner {

    public class Config {
        public String accessKeyId;
        public String secretAccessKey;
        public String bucket;
        public String region;
        public String cipherKey;
        public String host; // optional override; defaults to virtual-hosted style endpoint

        public String getHost() {
            return String.isNotBlank(host) ? host : bucket + '.s3.' + region + '.amazonaws.com';
        }
    }

    @TestVisible static Config configOverride;
    @TestVisible static Datetime nowOverride;
    static Config cachedConfig;

    public static Config getConfig() {
        if (configOverride != null) {
            return configOverride;
        }
        if (cachedConfig != null) {
            return cachedConfig;
        }

        Amazon_S3__mdt m = Amazon_S3__mdt.getInstance('Amazon_s3_integration');
        Boolean isSandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;

        Config c = new Config();
        c.accessKeyId = m.Access_Key_Id__c;
        c.secretAccessKey = m.Secret_Access_Key__c;
        c.cipherKey = m.URL_Encryption_Key__c;
        c.bucket = isSandbox ? m.Bucket_Sandbox__c : m.Bucket__c;
        c.region = isSandbox ? m.Region_Sandbox__c : m.Region__c;

        if (String.isBlank(c.accessKeyId) || String.isBlank(c.secretAccessKey)
                || String.isBlank(c.bucket) || String.isBlank(c.region)) {
            throw new S3Exception('Amazon S3 configuration is incomplete');
        }
        cachedConfig = c;
        return c;
    }

    /** Public (unsigned) object URL - not accessible for private objects, informational only. */
    public static String objectUrl(String key) {
        return 'https://' + getConfig().getHost() + '/' + encodePath(key);
    }

    /**
     * @param method     HTTP method the URL is valid for (GET, PUT, DELETE, HEAD)
     * @param key        object key, or '' / null for bucket-level operations (e.g. ListObjectsV2)
     * @param expiresSec validity in seconds (1 - 604800)
     * @param extra      additional query parameters to sign (lowercase names, e.g. 'prefix',
     *                   'list-type', 'response-content-disposition'); may be null
     */
    public static String presign(String method, String key, Integer expiresSec, Map<String, String> extra, Boolean encryptUrl) {
        return presign(method, key, expiresSec, extra, null, encryptUrl);
    }

    static String encrypt(String plainText, String cipherKey) {
        // AES-256-CBC, PKCS5 padding; the random 16-byte IV is prepended to the ciphertext
        Blob cipher = Crypto.encryptWithManagedIV('AES256', key(cipherKey), Blob.valueOf(plainText));
        return EncodingUtil.base64Encode(cipher);
    }

    static Blob key(String cipherKey) {
        if (String.isBlank(cipherKey)) {
            throw new AuraHandledException('URL cipher key is not configured.');
        }
        return EncodingUtil.base64Decode(cipherKey);
    }

    /**
     * As above, additionally signing request headers the client must send with exactly these
     * values (e.g. 'x-amz-checksum-crc32'). S3 rejects the request if they are missing or differ.
     *
     * @param signedHeaders lowercase header name => value; may be null
     */
    public static String presign(String method, String key, Integer expiresSec,
                                 Map<String, String> extra, Map<String, String> signedHeaders, Boolean encryptUrl) {
        Config cfg = getConfig();
        String host = cfg.getHost();

        Map<String, String> headers = new Map<String, String>{ 'host' => host };
        if (signedHeaders != null) {
            for (String h : signedHeaders.keySet()) {
                if (!h.equals(h.toLowerCase())) {
                    throw new S3Exception('Signed header names must be lowercase: ' + h);
                }
                headers.put(h, signedHeaders.get(h).trim());
            }
        }
        List<String> headerNames = new List<String>(headers.keySet());
        headerNames.sort(); // all lowercase, so case-insensitive sort == byte order
        String canonicalHeaders = '';
        for (String h : headerNames) {
            canonicalHeaders += h + ':' + headers.get(h) + '\n';
        }
        String signedHeaderList = String.join(headerNames, ';');

        Datetime now = nowOverride != null ? nowOverride : Datetime.now();
        String amzDate = now.formatGmt('yyyyMMdd\'T\'HHmmss\'Z\'');
        String dateStamp = now.formatGmt('yyyyMMdd');
        String scope = dateStamp + '/' + cfg.region + '/s3/aws4_request';

        // SigV4 requires query params sorted by byte order. Uppercase 'X-Amz-*' names sort
        // before any lowercase name, so they go first in this fixed order and the
        // (lowercase-only) extras are sorted and appended after them.
        List<String> params = new List<String>{
            'X-Amz-Algorithm=AWS4-HMAC-SHA256',
            'X-Amz-Credential=' + enc(cfg.accessKeyId + '/' + scope),
            'X-Amz-Date=' + amzDate,
            'X-Amz-Expires=' + expiresSec,
            'X-Amz-SignedHeaders=' + enc(signedHeaderList)
        };
        if (extra != null && !extra.isEmpty()) {
            List<String> names = new List<String>(extra.keySet());
            for (String n : names) {
                if (!n.equals(n.toLowerCase())) { // Apex '==' on strings is case-insensitive
                    throw new S3Exception('Extra query parameter names must be lowercase: ' + n);
                }
            }
            names.sort();
            for (String n : names) {
                params.add(enc(n) + '=' + enc(extra.get(n)));
            }
        }
        String canonicalQuery = String.join(params, '&');
        String canonicalUri = '/' + encodePath(key == null ? '' : key);

        String canonicalRequest = method + '\n'
            + canonicalUri + '\n'
            + canonicalQuery + '\n'
            + canonicalHeaders + '\n'
            + signedHeaderList + '\n'
            + 'UNSIGNED-PAYLOAD';

        String stringToSign = 'AWS4-HMAC-SHA256\n'
            + amzDate + '\n'
            + scope + '\n'
            + EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(canonicalRequest)));

        Blob signingKey = hmac(dateStamp, Blob.valueOf('AWS4' + cfg.secretAccessKey));
        signingKey = hmac(cfg.region, signingKey);
        signingKey = hmac('s3', signingKey);
        signingKey = hmac('aws4_request', signingKey);
        String signature = EncodingUtil.convertToHex(hmac(stringToSign, signingKey));

        if(encryptUrl) {
            return encrypt('https://' + host + canonicalUri + '?' + canonicalQuery + '&X-Amz-Signature=' + signature, cfg.cipherKey);
        } else {
            return 'https://' + host + canonicalUri + '?' + canonicalQuery + '&X-Amz-Signature=' + signature;
        }
    }

    static Blob hmac(String data, Blob key) {
        return Crypto.generateMac('hmacSHA256', Blob.valueOf(data), key);
    }

    /** RFC 3986 encoding as required by SigV4 (unreserved: A-Z a-z 0-9 - _ . ~). */
    public static String enc(String s) {
        return EncodingUtil.urlEncode(s, 'UTF-8')
            .replace('+', '%20')
            .replace('*', '%2A')
            .replace('%7E', '~');
    }

    /** Encodes each path segment, keeping the '/' separators. */
    @TestVisible
    static String encodePath(String key) {
        if (String.isEmpty(key)) {
            return '';
        }
        List<String> segments = new List<String>();
        for (String seg : key.split('/', -1)) {
            segments.add(enc(seg));
        }
        return String.join(segments, '/');
    }

    public class S3Exception extends Exception {}
}