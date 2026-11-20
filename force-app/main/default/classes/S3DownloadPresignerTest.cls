@IsTest
private class S3DownloadPresignerTest {

    static void useAwsExampleConfig() {
        S3DownloadPresigner.Config c = new S3DownloadPresigner.Config();
        c.accessKeyId = 'AKIAIOSFODNN7EXAMPLE';
        c.secretAccessKey = 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY';
        c.bucket = 'examplebucket';
        c.region = 'us-east-1';
        c.host = 'examplebucket.s3.amazonaws.com';
        S3DownloadPresigner.configOverride = c;
        S3DownloadPresigner.nowOverride = Datetime.newInstanceGmt(2013, 5, 24, 0, 0, 0);
    }

    // Reference vector from the AWS docs:
    // "Authenticating Requests: Using Query Parameters (AWS Signature Version 4)" - example GET
    @IsTest
    static void matchesAwsReferenceSignature() {
        useAwsExampleConfig();

        String url = S3DownloadPresigner.presign('GET', 'test.txt', 86400, null);

        Assert.areEqual(
            'https://examplebucket.s3.amazonaws.com/test.txt'
            + '?X-Amz-Algorithm=AWS4-HMAC-SHA256'
            + '&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request'
            + '&X-Amz-Date=20130524T000000Z'
            + '&X-Amz-Expires=86400'
            + '&X-Amz-SignedHeaders=host'
            + '&X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404',
            url);
    }

    @IsTest
    static void appendsSortedExtraParamsAfterAmzParams() {
        useAwsExampleConfig();

        String url = S3DownloadPresigner.presign('GET', '', 60,
            new Map<String, String>{ 'prefix' => 'Account/001/', 'list-type' => '2' });

        Assert.isTrue(url.startsWith('https://examplebucket.s3.amazonaws.com/?X-Amz-Algorithm='), url);
        Assert.isTrue(url.contains('X-Amz-SignedHeaders=host&list-type=2&prefix=Account%2F001%2F&X-Amz-Signature='), url);
    }

    @IsTest
    static void signsExtraHeaders() {
        useAwsExampleConfig();

        String plain = S3DownloadPresigner.presign('PUT', 'test.txt', 300, null);
        String withChecksum = S3DownloadPresigner.presign('PUT', 'test.txt', 300, null,
            new Map<String, String>{ 'x-amz-checksum-crc32' => 'y/Q5Jg==' });

        Assert.isTrue(plain.contains('&X-Amz-SignedHeaders=host&'), plain);
        Assert.isTrue(withChecksum.contains('&X-Amz-SignedHeaders=host%3Bx-amz-checksum-crc32&'), withChecksum);
        Assert.areNotEqual(
            plain.substringAfter('X-Amz-Signature='),
            withChecksum.substringAfter('X-Amz-Signature='),
            'Signed header must change the signature');
        // Header-less overload must still match the AWS reference vector
        Assert.areEqual(S3DownloadPresigner.presign('GET', 'test.txt', 86400, null),
            S3DownloadPresigner.presign('GET', 'test.txt', 86400, null, new Map<String, String>()));
    }

    @IsTest
    static void rejectsUppercaseSignedHeaders() {
        useAwsExampleConfig();
        try {
            S3DownloadPresigner.presign('PUT', 'a', 60, null, new Map<String, String>{ 'X-Amz-Checksum-Crc32' => 'x' });
            Assert.fail('Expected exception');
        } catch (S3DownloadPresigner.S3Exception e) {
            Assert.isTrue(e.getMessage().contains('lowercase'));
        }
    }

    @IsTest
    static void rejectsUppercaseExtraParams() {
        useAwsExampleConfig();
        try {
            S3DownloadPresigner.presign('GET', 'a', 60, new Map<String, String>{ 'Prefix' => 'x' });
            Assert.fail('Expected exception');
        } catch (S3DownloadPresigner.S3Exception e) {
            Assert.isTrue(e.getMessage().contains('lowercase'));
        }
    }

    @IsTest
    static void encodesPerRfc3986() {
        Assert.areEqual('a%20b~c-d_e.f%2A%2B', S3DownloadPresigner.enc('a b~c-d_e.f*+'));
        Assert.areEqual('Account/001/my%20file%20%281%29.zip', S3DownloadPresigner.encodePath('Account/001/my file (1).zip'));
        Assert.areEqual('', S3DownloadPresigner.encodePath(''));
    }

    @IsTest
    static void buildsDefaultHostAndObjectUrl() {
        S3DownloadPresigner.Config c = new S3DownloadPresigner.Config();
        c.accessKeyId = 'AK';
        c.secretAccessKey = 'SK';
        c.bucket = 'my-bucket';
        c.region = 'ap-south-1';
        S3DownloadPresigner.configOverride = c;

        Assert.areEqual('my-bucket.s3.ap-south-1.amazonaws.com', c.getHost());
        Assert.areEqual('https://my-bucket.s3.ap-south-1.amazonaws.com/a/b%20c.txt', S3DownloadPresigner.objectUrl('a/b c.txt'));
    }
}