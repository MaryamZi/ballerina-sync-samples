import ballerina/log;
import ballerina/sql;
import ballerina/time;

type ExistingDbEntry record {| 
    string id; 
    time:Civil lastModifiedDate;
|};

function getExistingDbEntries() returns map<ExistingDbEntry>|error {
    stream<ExistingDbEntry, error?> existingEntriesStrm = 
        dbClient->query(`SELECT [Contact].[id], [Contact].[lastModifiedDate] FROM [Contact]`);
    return map from ExistingDbEntry entry in existingEntriesStrm select [entry.id, entry];
}

function getContactInsertQuery(DbContact contact) returns sql:ParameterizedQuery =>
    `INSERT INTO [Contact] ( [id], [name], [phone], [fax], [email], [title], [address], [backupPostalCode], [isDeleted], [lastModifiedDate] ) VALUES (${
            contact.id},${
                contact.name},${
                    contact.phone},${
                        contact.fax},${
                            contact.email},${
                                contact.title},${
                                    contact.address},${
                                        contact.backupPostalCode},${
                                            contact.isDeleted},${
                                                contact.lastModifiedDate})`;

function getContactUpdateQuery(DbContact contact) returns sql:ParameterizedQuery =>
    `UPDATE [Contact] SET  [name] = ${contact.name
                        }, [phone] = ${contact.phone
                        }, [fax] = ${contact.fax
                        }, [email] = ${contact.email
                        }, [title] = ${contact.title
                        }, [address] = ${contact.address
                        }, [backupPostalCode] = ${contact.backupPostalCode
                        }, [isDeleted] = ${contact.isDeleted
                        }, [lastModifiedDate] = ${contact.lastModifiedDate
                        } WHERE  [Contact].[id] = ${contact.id}`;

function updateDatabase(DbContact[] dbContacts, FailureData failureData) returns error? {
    if dbContacts.length() == 0 {
        return;
    }

    map<ExistingDbEntry> existingEntries = check getExistingDbEntries();
    string[] existingEntriesIds = existingEntries.keys();

    DbContact[] newDbContacts = [];
    DbContact[] contactsToUpdate = [];

    int updatedContactCount = 0;

    foreach DbContact dbContact in dbContacts {
        string id = dbContact.id;
        if existingEntriesIds.indexOf(id) is () {
            newDbContacts.push(dbContact);
            continue;
        }
        updatedContactCount += 1;
        contactsToUpdate.push(dbContact);
    }

    string[] failedExistingContactIds = [];
    string[] failedNewContactIds = [];

    if updatedContactCount > 0 {
        sql:ParameterizedQuery[] updateQueries = 
            from DbContact contact in contactsToUpdate select getContactUpdateQuery(contact);
        sql:ExecutionResult[]|sql:Error updateStatus = batchExecute(updateQueries);
        
        if updateStatus is error {
            failedExistingContactIds = from DbContact {id} in contactsToUpdate select id;
            log:printError("Failed to update contact details in database", updateStatus, ids = failedExistingContactIds);
        }
    }

    if newDbContacts.length() > 0 {
        sql:ParameterizedQuery[] insertQueries = 
            from DbContact contact in newDbContacts select getContactInsertQuery(contact);
        sql:ExecutionResult[]|error insertStatus = batchExecute(insertQueries);

        if insertStatus is error {
            failedNewContactIds = from DbContact {id} in newDbContacts select id;
            log:printError("Failed to persist new contact details in in database", insertStatus);
        }
    }

    int failedExistingContactIdsLength = failedExistingContactIds.length();
    int failedNewContactIdsLength = failedNewContactIds.length();

    if failedExistingContactIdsLength + failedNewContactIdsLength == dbContacts.length() {
        // Return an error only if all failed.
        return error("Failed to update the database for contacts");
    }

    if failedExistingContactIdsLength == 0 && failedNewContactIdsLength == 0 {
        log:printInfo("Successfully updated the database for all out-of-date/new contacts", 
                      count = dbContacts.length());
        return;
    }

    string[] failedContactIds = [...failedExistingContactIds, ...failedNewContactIds];
    log:printError("Database update failed for some contacts", 
                   failedContactIds = failedContactIds,
                   successfulCount = dbContacts.length() - failedContactIds.length());
    failureData.databaseSyncFailedEntriesIds.push(...failedContactIds);
}

// Will be able to directly pass `dbBatchSize` to the `dbClient->batchExecute` method
// and remove this custom logic once https://github.com/ballerina-platform/ballerina-library/issues/4133 
// is supported.
function batchExecute(sql:ParameterizedQuery[] queries) returns sql:ExecutionResult[]|sql:Error {
    sql:ExecutionResult[] results = [];
    int totalQueryCount = queries.length();
    foreach int index in int:range(0, totalQueryCount, dbBatchSize) {
        int endIndex = index + dbBatchSize;
        sql:ParameterizedQuery[] batch = 
            queries.slice(index, endIndex > totalQueryCount ? totalQueryCount : endIndex);
        sql:ExecutionResult[] batchExecuteResult = check dbClient->batchExecute(batch);
        results.push(...batchExecuteResult);
    }
    return results;
}
