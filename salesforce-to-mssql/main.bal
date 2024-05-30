import ballerina/log;
import ballerina/sql;
import ballerina/time;

import ballerinax/mssql;
import ballerinax/mssql.driver as _;
import ballerinax/salesforce as sf;

configurable string sfBaseUrl = ?;
configurable string sfClientId = ?;
configurable string sfClientSecret = ?;
configurable string sfRefreshToken = ?;
configurable string sfRefreshUrl = ?;

configurable int dbPort = ?;
configurable string dbHost = ?;
configurable string dbUser = ?;
configurable string dbDatabase = ?;
configurable string dbPassword = ?;
configurable mssql:Options dbOptions = {};
configurable int dbBatchSize = 1000;

configurable byte? updateWindowInHours = ();

final sf:Client sfClient = check initSalesforceClient();

function initSalesforceClient() returns sf:Client|error => new ({
    baseUrl: sfBaseUrl,
    auth: {
        clientId: sfClientId,
        clientSecret: sfClientSecret,
        refreshUrl: sfRefreshUrl,
        refreshToken: sfRefreshToken
    }
});

final sql:Client dbClient = check new mssql:Client(dbHost, dbUser, dbPassword, dbDatabase, dbPort, options = dbOptions);

const string QUERY = "SELECT Id, FirstName, LastName, Phone, Fax, Email, Title, MailingStreet, MailingCity, MailingState, MailingCountry, IsDeleted, LastModifiedDate, OtherPostalCode FROM Contact";

public function main() returns error? {
    do {
        if dbBatchSize <= 0 {
            fail error(string `Invalid batch size ${dbBatchSize}, expected a value greater than zero.`);
        }

        FailureData failureData = {};
        
        Contact[]? contactsRequiringUpdates = check queryBatch(getQuery(), failureData);
        if contactsRequiringUpdates is () {
            return;
        }
        
        DbContact[] dbContacts = check transformContacts(contactsRequiringUpdates, failureData);
        
        check updateDatabase(dbContacts, failureData);

        logPartialFailureDetailsAndSendEmail(failureData);
    } on fail error err {
        log:printError("Failed to sync data", err);
        sendEmailForSyncFailure(err.message());
        return err;
    }
}

function getQuery() returns string {
    string query = QUERY;

    if updateWindowInHours is byte {
        time:Utc utcRequired = time:utcAddSeconds(time:utcNow(), <decimal>updateWindowInHours * 60 * 60 * -1);
        query += string ` WHERE LastModifiedDate > ${time:utcToString(utcRequired)}`;
    }                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             

    return query;
}

function transformContacts(Contact[] contacts, FailureData failureData) returns DbContact[]|error {
    DbContact[] dbContacts = [];
    Contact[] failedEntries = [];

    foreach Contact contact in contacts {
        DbContact|error dbContact = transformContact(contact);
        if dbContact is DbContact {
            dbContacts.push(dbContact);
            continue;
        }
        failedEntries.push(contact);
    }

    if failedEntries.length() != 0 {
        failureData.transformationFailedEntries = failedEntries;
    }

    if dbContacts.length() == 0 {
        return error("Transformation failed for all entries due to value mismatches. Sample: " + 
                        contacts[0].toString());
    }
    return dbContacts;
}

function transformContact(Contact contact) returns DbContact|error => 
    {
        id: check validateNonEmptyString(contact.Id),
        name: string `${check validateNonEmptyString(contact.FirstName)} ${
                        check validateNonEmptyString(contact.LastName)}`,
        phone: getNonEmptyStringValue(contact.Phone),
        fax: getNonEmptyStringValue(contact.Fax),
        email: getNonEmptyStringValue(contact.Email),
        title: getNonEmptyStringValue(contact.Title),
        address: transformAddress(contact.MailingStreet, contact.MailingCity, contact.MailingState, contact.MailingCountry),
        backupPostalCode: check parseNonEmptyStringAsIntValue(contact.OtherPostalCode),
        isDeleted: check boolean:fromString(contact.IsDeleted),
        lastModifiedDate: check time:civilFromString(contact.LastModifiedDate)
    };

function transformAddress(string mailingStreet, string mailingCity, string mailingState, string mailingCountry) returns string? => 
    let string address = string:'join(", ", ...from string component in [mailingStreet, mailingCity, mailingState, mailingCountry]
                            let string? nilableComponent = getNonEmptyStringValue(component)
                            where nilableComponent is string
                            select nilableComponent)
    in getNonEmptyStringValue(address);

function queryBatch(string query, FailureData failureData) returns Contact[]|error? {
    log:printInfo("Querying Salesforce data", query = query);

    sf:BulkJobInfo {id} = check queryAndWait(query);

    log:printInfo("Retrieving Salesforce query results", jobId = id);

    string[][] csvData = check sfClient->getQueryResult(id);
    
    if csvData.length() < 2 {
        log:printInfo("No new data was retrieved from Salesforce", jobId = id);
        return;
    }

    log:printInfo("Successfully retrieved data from Salesforce", count = csvData.length() - 1, jobId = id);

    string[][]? dataRequiringUpdates = check filterOutUpToDateData(csvData);
    if dataRequiringUpdates is () {
        return;
    }

    return transformCSVToRecords(dataRequiringUpdates, failureData);
}

function queryAndWait(string query) returns sf:BulkJobInfo|error {
    future<sf:BulkJobInfo|error> queryFuture = check sfClient->createQueryJobAndWait({
        operation: "query",
        query
    });

    sf:BulkJobInfo bulkJobInfo = check wait queryFuture;
    if bulkJobInfo.state is sf:FAILED|sf:ABORTED {
        log:printError("Failed to retrieve data", id = bulkJobInfo.id, state = bulkJobInfo.state);
        return error("Failed to retrieve data", id = bulkJobInfo.id, state = bulkJobInfo.state);
    }
    return bulkJobInfo;
}

function filterOutUpToDateData(string[][] csvData) returns string[][]|error? {
    string[] headers = csvData[0];
    string[][] dataRequiringUpdates = [headers];
    
    int? idIndex = headers.indexOf("Id");
    int? lastModifiedDateIndex = headers.indexOf("LastModifiedDate");
    if idIndex is () || lastModifiedDateIndex is () {
        return error("Required 'Id' and/or 'LastModifiedDate' field(s) not found in Salesforce data");
    }

    map<ExistingDbEntry> existingEntries = check getExistingDbEntries();
    string[] existingEntriesIds = existingEntries.keys();

    int ignoredUpToDateContactCount = 0;

    foreach int index in 1 ..< csvData.length() {
        string[] row = csvData[index];

        string idValue = row[idIndex];
        if existingEntriesIds.indexOf(idValue) is () {
            dataRequiringUpdates.push(row);
            continue;
        }

        // If the last modified time from Salesforce is the same as that in the database, 
        // filter that entry out.
        if isSameTime(check time:civilFromString(row[lastModifiedDateIndex]), 
                      existingEntries.get(idValue).lastModifiedDate) {
            log:printDebug("Ignoring up-to-date entry for database update", id = idValue);
            ignoredUpToDateContactCount += 1;
            continue;
        }
        dataRequiringUpdates.push(row);
    }
    if ignoredUpToDateContactCount == csvData.length() - 1 {
        log:printInfo("The database is up-to-date for all contacts, no new updates were done");
        return;
    }
    return dataRequiringUpdates;
}

function transformCSVToRecords(string[][] csvData, FailureData failureData) returns Contact[]|error {
    string[] headers = csvData[0];
    int headersLength = headers.length();

    map<string>[] mappings = from int rowIndex in 1 ..< csvData.length()
                                let string[] row = csvData[rowIndex]
                                select map from int columnIndex in 0 ..< headersLength
                                    select [headers[columnIndex], row[columnIndex]];

    // If one conversion attempt fails everything would fail, and if one passes everything would pass.
    map<string> sfData = mappings[0];
    Contact|error contactData = sfData.cloneWithType();
    if contactData is error {
        return error("Required fields not found in the data retrieved from Salesforce. Received headers: " + 
                        headers.toString());
    }

    populateIgnoredKeyInfo(contactData, failureData);
    return mappings.cloneWithType();
}

function isSameTime(time:Civil t1, time:Civil t2) returns boolean {
    time:Civil {timeAbbrev: _, dayOfWeek: _, ...dbT1} = t1;
    return dbT1 == t2;
}
