import ballerina/log;
import ballerina/sql;
import ballerina/time;

import ballerinax/mssql;
import ballerinax/mssql.driver as _;
import ballerinax/salesforce as sf;

// Specify values that can change by environment and/or run as `configurable`
// variables. These can be overridden via configuration files, environment variables,
// and CLI arguments - https://ballerina.io/learn/provide-values-to-configurable-variables/

// Salesforce configuration.
configurable string sfBaseUrl = ?;
configurable string sfClientId = ?;
configurable string sfClientSecret = ?;
configurable string sfRefreshToken = ?;
configurable string sfRefreshUrl = ?;

configurable int? sfMaxRecords = ();

// Database configuration.
configurable int dbPort = ?;
configurable string dbHost = ?;
configurable string dbUser = ?;
configurable string dbDatabase = ?;
configurable string dbPassword = ?;
configurable mssql:Options dbOptions = {};
// Batch size for database operations, defaults to 1000, same as built-in Ballerina limit.
configurable int dbBatchSize = 1000;

// Update window configuration.
// Allows retrieving only entries that were updated within the specified number of hours.
// If unspecified, retrieves all data.
configurable byte? updateWindowInHours = ();

// The Salesforce connector instance that is used for Salesforce operations.
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

// The SQL connector instance that is used for database operations.
final sql:Client dbClient = check new mssql:Client(dbHost, dbUser, dbPassword, dbDatabase, dbPort, options = dbOptions);

// The Salesforce query that is used to retireve data.
// Can also be a variable instead.
const string QUERY = "SELECT Id, FirstName, LastName, Phone, Fax, Email, Title, MailingStreet, MailingCity, MailingState, MailingCountry, IsDeleted, LastModifiedDate, OtherPostalCode FROM Contact";

public function main() returns error? {
    do {
        // Validate that the specified Salesforce and database batch sizes are greater than zero.
        if dbBatchSize <= 0 {
            fail error(string `Invalid batch size: ${dbBatchSize}, expected a value greater than zero.`);
        }
        if sfMaxRecords is int && sfMaxRecords <= 0 {
            fail error(string `Invalid value for Salesfoce Max Records: ${
                        <int> sfMaxRecords}, expected a value greater than zero.`);
        }

        check syncData();
    } on fail error err {
        // Control is transferred here if a failure occured for all data and/or a complete chunk.
        log:printError("Failed to sync data", err);
        // Send an email about the failure if configured to do so.
        sendEmailForSyncFailure(err.message());
        return err;
    }
}

function syncData() returns error? {
    string query = getQuery();
    log:printInfo("Querying Salesforce data", query = query);

    // Create the query job and wait for its completion.
    // The `id` of the bulk job is extracted to retrieve the results. 
    sf:BulkJobInfo {id} = check queryAndWait(query);

    // `FailureData` is used to collect partial failure data (e.g., due to invalid values, 
    // insufficient fields, etc.) to give detailed information on partial or full failure.
    FailureData failureData = {};
    check syncDataChunks(id, failureData);
    // Log partial failure data and send an email about failures if configured to do so.
    logPartialFailureDetailsAndSendEmail(failureData);    
}

// Build the final SOQL query for Salesforce. Incorporates a WHERE clause if `updateWindowInHours` 
// was specified to retrieve only data that was updated within the specified number of hours.
function getQuery() returns string {
    string query = QUERY;

    if updateWindowInHours is byte {
        time:Utc utcRequired = time:utcAddSeconds(time:utcNow(), <decimal>updateWindowInHours * 60 * 60 * -1);
        query += string ` WHERE LastModifiedDate > ${time:utcToString(utcRequired)}`;
    }                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             

    return query;
}

function syncDataChunks(string id, FailureData failureData) returns error? {
    int pageNumber = 1;
    while true {
        // Retrieve data from Salesforce.
        Contact[]? contacts = check retrieveChunk(id, failureData, pageNumber);
        // Nil indicates that all data has been retrieved.
        if contacts is () {
            return;
        }

        // No entries requiring updates in the specific chunk.
        if contacts.length() == 0 {
            continue;
        }
        
        // Transform data from Salesforce to the format expected by the database.
        // The actual transformation of individual entries is done via data mapper.
        DbContact[] dbContacts = check transformContacts(contacts, failureData);
        
        // Update the database for successfully transformed values.
        check updateDatabase(dbContacts, failureData); 
        pageNumber += 1;
    }   
}

// Function to retrieve data from Salesforce in chunks.
// Data retrieved in CSV format is then converted to an array of records, ensuring all
// the expected fields are present.
function retrieveChunk(string id, FailureData failureData, int pageNumber) returns Contact[]|error? {
    log:printInfo("Retrieving Salesforce query results", pageNumber = pageNumber, jobId = id);

    // Retrieve the CSV data by specifying the job ID and max record size. 
    string[][] csvData = check sfClient->getQueryResult(id, sfMaxRecords);
    
    if csvData.length() < 2 {
        log:printInfo("No more data to retrieve", pageNumber = pageNumber, jobId = id);
        return ();
    }

    log:printInfo("Successfully retrieved data from Salesforce", pageNumber = pageNumber, 
                    entryCount = csvData.length() - 1, jobId = id);

    // Filter out up to date data to avoid transformation and updates of the database for already
    // up to date data.
    // The `LastModifiedDate` value is compared with that in the database to see if an update is required.
    string[][] dataRequiringUpdates = check filterOutUpToDateData(csvData, pageNumber);
    if dataRequiringUpdates.length() == 0 {
        return [];
    }

    // Transform the entries requiring updates to records.
    return transformCSVToRecords(dataRequiringUpdates, failureData, pageNumber);
}

// Create the query job and wait for its completion.
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

// Transform a set of entries from the Salesforce representation to the format expected by the database.
function transformContacts(Contact[] contacts, FailureData failureData) returns DbContact[]|error {
    DbContact[] dbContacts = [];
    Contact[] failedEntries = failureData.transformationFailedEntries;

    foreach Contact contact in contacts {
        DbContact|error dbContact = transformContact(contact);
        if dbContact is DbContact {
            dbContacts.push(dbContact);
            continue;
        }
        failedEntries.push(contact);
    }

    if dbContacts.length() == 0 {
        return error("Transformation failed for all entries due to value mismatches. Sample: " + 
                        contacts[0].toString());
    }
    return dbContacts;
}

// Transform Contact data from the Salesforce representation to the format expected by the database.
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

// Function to combine non-empty address components to an address string.
function transformAddress(string mailingStreet, string mailingCity, string mailingState, string mailingCountry) returns string? => 
    let string address = string:'join(", ", ...from string component in [mailingStreet, mailingCity, mailingState, mailingCountry]
                            let string? nilableComponent = getNonEmptyStringValue(component)
                            where nilableComponent is string
                            select nilableComponent)
    in getNonEmptyStringValue(address);

// Filter out up to date data and return only the data requiring database updates.
function filterOutUpToDateData(string[][] csvData, int pageNumber) returns string[][]|error {
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
        log:printInfo("The database is up-to-date for all contacts, no new updates were done", 
                        pageNumber = pageNumber);
        return [];
    }
    return dataRequiringUpdates;
}

function transformCSVToRecords(string[][] csvData, FailureData failureData, int pageNumber) returns Contact[]|error {
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
                        headers.toString(), pageNumber = pageNumber);
    }

    populateIgnoredKeyInfo(contactData, failureData);
    return mappings.cloneWithType();
}

// Check if two time values are the same.
function isSameTime(time:Civil t1, time:Civil t2) returns boolean {
    time:Civil {timeAbbrev: _, dayOfWeek: _, ...dbT1} = t1;
    return dbT1 == t2;
}
