import ballerina/lang.regexp;
import ballerina/sql;
import ballerina/test;
import ballerina/time;

import ballerinax/googleapis.gmail;
import ballerinax/salesforce as sf;

isolated string? emailSubject = ();
isolated string? emailBody = ();

@test:BeforeSuite
@test:AfterSuite
function cleanUpDb() returns error? {
    _ = check dbClient->execute(`DELETE from Contact`);
}

@test:AfterEach
function afterTest() {
    setEmailSubject(());
    setEmailBody(());
}

@test:Mock {
    functionName: "initSalesforceClient"
}
function getMockSFClient() returns sf:Client|error => test:mock(sf:Client);

@test:Mock {
    functionName: "initGmailClient"
}
function getMockGmailClient() returns gmail:Client|error => 
    test:mock(gmail:Client, new MockGmailClient());

@test:Config
function testSuccessfulSync() returns error? {
    test:prepare(sfClient)
        .when("createQueryJobAndWait")
        .thenReturn(getPlaceholderJobInfoFuture());

    string[][] mockData = [
        ["Id", "FirstName", "LastName", "Phone", "Fax", "Email", "Title", "MailingStreet", "MailingCity", "MailingState", "MailingCountry", "IsDeleted", "LastModifiedDate", "OtherPostalCode"],
        ["004ab000000cdEFGHI", "John", "Doe", "(011) 111-1111", "(012) 111-1111", "john@test.com", "SVP, Procurement", "20 Main Av.", "NYC", "NY", "USA", "false", "2024-05-20T07:32:52.000Z", ""],
        ["004ab000000cdEFGHJ", "Jane", "Doe", "(011) 111-1112", "(012) 111-1112", "jane@test.com", "Director", "", "", "", "", "true", "2024-05-20T08:40:10.000Z", "6400"]
    ];

    test:prepare(sfClient)
        .when("getQueryResult")
        .thenReturn(<string[][]>mockData);

    check main();

    stream<DbContact, sql:Error?> dbEntriesStrm = dbClient->query(`SELECT * FROM Contact`);
    DbContact[] dbEntries = check from DbContact dbContact in dbEntriesStrm
        select dbContact;

    test:assertEquals(dbEntries.length(), mockData.length() - 1);

    DbContact dbContact = dbEntries[0];
    test:assertEquals(dbContact.id, "004ab000000cdEFGHI");
    test:assertEquals(dbContact.name, "John Doe");
    test:assertEquals(dbContact.phone, "(011) 111-1111");
    test:assertEquals(dbContact.fax, "(012) 111-1111");
    test:assertEquals(dbContact.email, "john@test.com");
    test:assertEquals(dbContact.title, "SVP, Procurement");
    test:assertEquals(dbContact.address, "20 Main Av., NYC, NY, USA");
    test:assertFalse(dbContact.isDeleted);
    test:assertEquals(dbContact.lastModifiedDate, <time:Civil>{year: 2024, month: 5, day: 20, hour: 7, minute: 32, second: 52});
    test:assertEquals(dbContact.backupPostalCode, ());

    dbContact = dbEntries[1];
    test:assertEquals(dbContact.id, "004ab000000cdEFGHJ");
    test:assertEquals(dbContact.name, "Jane Doe");
    test:assertEquals(dbContact.phone, "(011) 111-1112");
    test:assertEquals(dbContact.fax, "(012) 111-1112");
    test:assertEquals(dbContact.email, "jane@test.com");
    test:assertEquals(dbContact.title, "Director");
    test:assertEquals(dbContact.address, ());
    test:assertTrue(dbContact.isDeleted);
    test:assertEquals(dbContact.lastModifiedDate, <time:Civil>{year: 2024, month: 5, day: 20, hour: 8, minute: 40, second: 10});
    test:assertEquals(dbContact.backupPostalCode, 6400);
}


@test:Config {
    after: cleanUpDb,
    dependsOn: [testSuccessfulSync]
}
function testSuccessfulSyncWithUpdates() returns error? {
    test:prepare(sfClient)
        .when("createQueryJobAndWait")
        .thenReturn(getPlaceholderJobInfoFuture());

    string[][] mockData = [
        ["Id", "FirstName", "LastName", "Phone", "Fax", "Email", "Title", "MailingStreet", "MailingCity", "MailingState", "MailingCountry", "IsDeleted", "LastModifiedDate", "OtherPostalCode"],
        ["004ab000000cdEFGHI", "John", "Doe", "(011) 111-1111", "(012) 111-1111", "john@test.com", "SVP, Procurement", "20 Main Av.", "NYC", "NY", "USA", "false", "2024-05-20T07:32:52.000Z", ""],
        ["004ab000000cdEFGHJ", "Jane", "Doe", "(011) 111-1112", "(012) 111-1112", "jane@test.com", "Director", "22 Fuller Street", "NYC", "NY", "USA", "false", "2024-05-22T08:55:20.000Z", "6400"],
        ["004ab000000cdEFGIJ", "Mary", "Anne", "(011) 111-1113", "(012) 111-1113", "mary@test.com", "Engineer", "", "", "", "", "false", "2024-05-22T09:12:20.000Z", ""]
    ];

    test:prepare(sfClient)
        .when("getQueryResult")
        .thenReturn(<string[][]>mockData);

    check main();

    stream<DbContact, sql:Error?> dbEntriesStrm = dbClient->query(`SELECT * FROM Contact`);
    DbContact[] dbEntries = check from DbContact dbContact in dbEntriesStrm
        select dbContact;

    test:assertEquals(dbEntries.length(), mockData.length() - 1);

    DbContact dbContact = dbEntries[0];
    test:assertEquals(dbContact.id, "004ab000000cdEFGHI");
    test:assertEquals(dbContact.name, "John Doe");
    test:assertEquals(dbContact.phone, "(011) 111-1111");
    test:assertEquals(dbContact.fax, "(012) 111-1111");
    test:assertEquals(dbContact.email, "john@test.com");
    test:assertEquals(dbContact.title, "SVP, Procurement");
    test:assertEquals(dbContact.address, "20 Main Av., NYC, NY, USA");
    test:assertFalse(dbContact.isDeleted);
    test:assertEquals(dbContact.lastModifiedDate, <time:Civil>{year: 2024, month: 5, day: 20, hour: 7, minute: 32, second: 52});
    test:assertEquals(dbContact.backupPostalCode, ());

    dbContact = dbEntries[1];
    test:assertEquals(dbContact.id, "004ab000000cdEFGHJ");
    test:assertEquals(dbContact.name, "Jane Doe");
    test:assertEquals(dbContact.phone, "(011) 111-1112");
    test:assertEquals(dbContact.fax, "(012) 111-1112");
    test:assertEquals(dbContact.email, "jane@test.com");
    test:assertEquals(dbContact.title, "Director");
    test:assertEquals(dbContact.address, "22 Fuller Street, NYC, NY, USA");
    test:assertFalse(dbContact.isDeleted);
    test:assertEquals(dbContact.lastModifiedDate, <time:Civil>{year: 2024, month: 5, day: 22, hour: 8, minute: 55, second: 20});
    test:assertEquals(dbContact.backupPostalCode, 6400);
    
    dbContact = dbEntries[2];
    test:assertEquals(dbContact.id, "004ab000000cdEFGIJ");
    test:assertEquals(dbContact.name, "Mary Anne");
    test:assertEquals(dbContact.phone, "(011) 111-1113");
    test:assertEquals(dbContact.fax, "(012) 111-1113");
    test:assertEquals(dbContact.email, "mary@test.com");
    test:assertEquals(dbContact.title, "Engineer");
    test:assertEquals(dbContact.address, ());
    test:assertFalse(dbContact.isDeleted);
    test:assertEquals(dbContact.lastModifiedDate, <time:Civil>{year: 2024, month: 5, day: 22, hour: 9, minute: 12, second: 20});
    test:assertEquals(dbContact.backupPostalCode, ());
}

@test:Config {
    dependsOn: [testSuccessfulSyncWithUpdates]
}
function testInsufficientFieldsFromSF() {
    test:prepare(sfClient)
        .when("createQueryJobAndWait")
        .thenReturn(getPlaceholderJobInfoFuture());

    string[][] mockData = [
        ["Id", "FirstName", "Phone", "Fax", "Email", "Title", "MailingStreet", "MailingCity", "MailingState", "MailingCountry", "IsDeleted", "LastModifiedDate", "OtherPostalCode"],
        ["004ab000000cdEFGHK", "John", "(011) 111-1111", "(012) 111-1111", "john@test.com", "SVP, Procurement", "20 Main Av.", "NYC", "NY", "USA", "false", "2024-05-20T07:32:52.000Z",""],
        ["004ab000000cdEFGHL", "Jane", "(011) 111-1112", "(012) 111-1112", "jane@test.com", "Director", "", "", "", "", "false", "2024-05-20T08:40:10.000Z",""]
    ];

    test:prepare(sfClient)
        .when("getQueryResult")
        .thenReturn(<string[][]>mockData);

    error? mainResult = main();
    test:assertTrue(mainResult is error);

    assertEmailSubject("Salesforce to MS SQL Sync Failed");
    string emailBodyString;
    lock {
        if emailBody is () {
            test:assertFail();
        }
        emailBodyString = <string> emailBody;
    }
    test:assertTrue(emailBodyString.includes("failed: "));
    string[] split = regexp:split(re `failed: `, emailBodyString);
    test:assertTrue(regexp:isFullMatch(re `Sync task at 2[0-9\-T:.]*Z `, split[0]));
    string expected = string `Required fields not found in the data retrieved from Salesforce. Received headers: ` + 
        string `["Id","FirstName","Phone","Fax","Email","Title","MailingStreet","MailingCity","MailingState","MailingCountry","IsDeleted","LastModifiedDate","OtherPostalCode"]`;
    test:assertEquals(split[1], expected);
}

@test:Config {
    dependsOn: [testInsufficientFieldsFromSF],
    after: cleanUpDb
}
function testAdditionalFieldsFromSF() returns error? {
    test:prepare(sfClient)
        .when("createQueryJobAndWait")
        .thenReturn(getPlaceholderJobInfoFuture());

    string[][] mockData = [
        ["Id", "FirstName", "LastName", "Name", "Phone", "Fax", "Email", "Title", "MailingStreet", "MailingCity", "MailingState", "MailingCountry", "IsDeleted", "LastModifiedDate", "OtherPostalCode"],
        ["004ab000000cdEFGHM", "John", "Doe", "John D", "(011) 111-1111", "(012) 111-1111", "john@test.com", "SVP, Procurement", "20 Main Av.", "NYC", "NY", "USA", "false", "2024-05-20T07:32:52.000Z", ""],
        ["004ab000000cdEFGHN", "Jane", "Doe", "Jane D", "(011) 111-1112", "(012) 111-1112", "jane@test.com", "Director", "", "", "", "", "true", "2024-05-20T08:40:10.000Z", "6400"]
    ];

    test:prepare(sfClient)
        .when("getQueryResult")
        .thenReturn(<string[][]>mockData);

    check main();

    assertEmailSubject("Salesforce to MS SQL Sync Failed for Some Records");
    assertEmailBody("Ignored extra Salesforce field(s): Name");
}

@test:Config {
    dependsOn: [testAdditionalFieldsFromSF],
    after: cleanUpDb
}
function testFieldsOfInvalidTypesFromSF() returns error? {
    test:prepare(sfClient)
        .when("createQueryJobAndWait")
        .thenReturn(getPlaceholderJobInfoFuture());

    string[][] mockData = [
        ["Id", "FirstName", "LastName", "Phone", "Fax", "Email", "Title", "MailingStreet", "MailingCity", "MailingState", "MailingCountry", "IsDeleted", "LastModifiedDate", "OtherPostalCode"],
        // Note that this entry's `IsDeleted` field is `yes` instead of `true`.
        ["004ab000000cdEFGHO", "John", "Doe", "(011) 111-1111", "(012) 111-1111", "john@test.com", "SVP, Procurement", "20 Main Av.", "NYC", "NY", "USA", "yes", "2024-05-20T07:32:52.000Z", ""],
        ["004ab000000cdEFGHP", "Jane", "Doe", "(011) 111-1112", "(012) 111-1112", "jane@test.com", "Director", "", "", "", "", "true", "2024-05-20T08:40:10.000Z", "6400"]
    ];

    test:prepare(sfClient)
        .when("getQueryResult")
        .thenReturn(<string[][]>mockData);

    check main();

    assertEmailSubject("Salesforce to MS SQL Sync Failed for Some Records");
    string emailBodyString;
    lock {
        if emailBody is () {
            test:assertFail();
        }
        emailBodyString = <string> emailBody;
    }
    test:assertTrue(emailBodyString.includes("had failures."));
    string[] split = regexp:split(re `had failures.`, emailBodyString);
    test:assertTrue(regexp:isFullMatch(re `Sync attempt at 2[0-9\-T:.]*Z `, split[0]));

    string expected = string `${"\n\n"
        } Transformation to target database type failed for the following entries due to invalid values: ${"\n\t"
        } 1. {"Id":"004ab000000cdEFGHO","FirstName":"John","LastName":"Doe","Phone":"(011) 111-1111","Fax":"(012) 111-1111","Email":"john@test.com","Title":"SVP, Procurement","MailingStreet":"20 Main Av.","MailingCity":"NYC","MailingState":"NY","MailingCountry":"USA","OtherPostalCode":"","IsDeleted":"yes","LastModifiedDate":"2024-05-20T07:32:52.000Z"}`;
    test:assertEquals(split[1], expected);

    // Assert that the update for the valid data has happened.
    stream<DbContact, sql:Error?> dbEntriesStrm = dbClient->query(`SELECT * FROM Contact`);
    DbContact[] dbEntries = check from DbContact dbContact in dbEntriesStrm select dbContact;
    test:assertEquals(dbEntries.length(), 1);
    DbContact dbContact = dbEntries[0];
    test:assertEquals(dbContact.id, "004ab000000cdEFGHP");
    test:assertEquals(dbContact.name, "Jane Doe");
    test:assertEquals(dbContact.phone, "(011) 111-1112");
    test:assertEquals(dbContact.fax, "(012) 111-1112");
    test:assertEquals(dbContact.email, "jane@test.com");
    test:assertEquals(dbContact.title, "Director");
    test:assertEquals(dbContact.address, ());
    test:assertTrue(dbContact.isDeleted);
    test:assertEquals(dbContact.lastModifiedDate, <time:Civil>{year: 2024, month: 5, day: 20, hour: 8, minute: 40, second: 10});
    test:assertEquals(dbContact.backupPostalCode, 6400);
}

function assertEmailSubject(string expected) {
    lock {
        test:assertEquals(emailSubject, expected);
    }
}

function assertEmailBody(string expected) {
    lock {
        test:assertEquals(emailBody, expected);
    }
}

function getPlaceholderJobInfoFuture() returns future<sf:BulkJobInfo> {
    worker JobInfoWorker returns sf:BulkJobInfo {
        return {
            createdDate: "",
            apiVersion: 0.0,
            'object: "",
            systemModstamp: "",
            id: "test-id",
            state: "",
            operation: "",
            contentType: "",
            createdById: "",
            concurrencyMode: ""
        };
    }
    return JobInfoWorker;
}

client class MockGmailClient {
    resource isolated function post users/[string userId]/messages/send(
            gmail:MessageRequest payload, gmail:Xgafv? xgafv = (), string? access_token = (), gmail:Alt? alt = (), string? callback = (),
            string? fields = (), string? 'key = (), string? oauth_token = (), boolean? prettyPrint = (),
            string? quotaUser = (), string? upload_protocol = (), string? uploadType = ())
                    returns gmail:Message|error {
        setEmailSubject(payload.subject);
        setEmailBody(payload.bodyInText);
        return {threadId: "test-mail-id", id: "test-mail-id"};
    }
}

isolated function setEmailSubject(string? subject) {
    lock {
        emailSubject = subject;
    }
}

isolated function setEmailBody(string? body) {
    lock {
        emailBody = body;
    }
}
