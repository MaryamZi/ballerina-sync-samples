import ballerina/log;
import ballerina/time;

import ballerinax/googleapis.gmail;

configurable string[]? toEmailAddresses = ();
configurable string? gmailRefreshToken = ();
configurable string? gmailClientId = ();
configurable string? gmailClientSecret = ();

function sendEmailForSyncFailure(string errMessage) {
    if isEmailConfigUnspecified() {
        log:printDebug("Not sending notification email since email config is not specified.");
        return;
    }

    do {
        gmail:Client gmail = check initGmailClient();

        gmail:MessageRequest message = {
            to: toEmailAddresses,
            subject: "Salesforce to MS SQL Sync Failed",
            bodyInText: string `Sync task at ${time:utcToString(time:utcNow())} failed: ${errMessage}`
        };

        gmail:Message {threadId} = check gmail->/users/me/messages/send.post(message);
        log:printInfo("Successfully notified Salesforce to MS SQL sync failure via email", threadId = threadId);
    } on fail error err {
        log:printError("Failed to notify Salesforce to MS SQL sync failure via email", err);
    }
}

type FailureData record {|
    Contact[] transformationFailedEntries?;
    string[] databaseSyncFailedEntriesIds?;
    string[] ignoredFields?;
|};

function populateIgnoredKeyInfo(Contact contact, FailureData failureData) {
    string[] ignoredFields = [];
    // TODO: can be done in a better way U9 onward, using projection
    foreach string key in contact.keys() {
        string|error removeResult = trap contact.remove(key);
        if removeResult !is error {
            // If it was not an error (i.e., removal is possible), it was a rest field, 
            // and therefore, not required for the sync.
            ignoredFields.push(key);
        }
    }
    
    if ignoredFields.length() != 0 {
        failureData.ignoredFields = ignoredFields;
    }
}

function logPartialFailureDetailsAndSendEmail(FailureData failureData) {
    string emailBody = "";

    string? failureString = constructFailureString(failureData);
    if failureString is string {
        emailBody = failureString;
        log:printError("Failed to process some records", failures = failureString);
    }

    string[]? ignoredFields = failureData.ignoredFields;
    if ignoredFields !is () {
        string ignoredFieldsStr = string:'join(", ", ...ignoredFields);
        log:printWarn("Ignored extra Salesforce field(s)", fields = ignoredFieldsStr);
        
        if emailBody.length() != 0 {
            emailBody += "\n\n";
        }
        emailBody += "Ignored extra Salesforce field(s): " + ignoredFieldsStr;
    }

    if emailBody == "" {
        return;
    }

    if toEmailAddresses is () {
        log:printDebug("Not sending notification email since email config is not specified.");
        return;
    }
    sendPartialFailureEmail(emailBody);
}

function sendPartialFailureEmail(string emailBody) {
    do {
        gmail:Client gmail = check initGmailClient();

        gmail:MessageRequest message = {
            to: toEmailAddresses,
            subject: "Salesforce to MS SQL Sync Failed for Some Records",
            bodyInText: emailBody
        };

        gmail:Message {threadId} = check gmail->/users/me/messages/send.post(message);
        log:printInfo("Successfully notified partial failure data via email", threadId = threadId);
    } on fail error err {
        log:printError("Failed to notify partial failure data via email", err);
    }
}

function isEmailConfigUnspecified() returns boolean {
    return toEmailAddresses is () || gmailClientId is () || gmailClientSecret is () || gmailRefreshToken is ();
}

function initGmailClient() returns gmail:Client|error =>
    new gmail:Client({
        auth: <gmail:OAuth2RefreshTokenGrantConfig> {
            clientId: check gmailClientId.ensureType(),
            clientSecret: check gmailClientSecret.ensureType(),
            refreshToken: check gmailRefreshToken.ensureType()
        }
    });

function constructFailureString(FailureData failureData) returns string? {
    Contact[]? transformationFailedEntries = failureData.transformationFailedEntries;
    string[]? databaseSyncFailedEntriesIds = failureData.databaseSyncFailedEntriesIds;

    if transformationFailedEntries is () && databaseSyncFailedEntriesIds is ()  {
        return;
    }

    string failureString = string `Sync attempt at ${time:utcToString(time:utcNow())} had failures.`;

    if transformationFailedEntries !is () {
        failureString += "\n\n Transformation to target database type failed for the following entries due to invalid values: ";
        failureString += <string> from [int, map<string>] [index, entry] in transformationFailedEntries.enumerate()
                            select string `${"\n\t"} ${index + 1}. ${entry.toString()}`;
    }

    if databaseSyncFailedEntriesIds !is () {
        failureString += "\n\n Database update failed for the following IDs: ";
        failureString += <string> from [int, string] [index, id] in databaseSyncFailedEntriesIds.enumerate()
                            select string `${"\n\t"} ${index + 1}. ${id}`;
    }

    return failureString;
}
