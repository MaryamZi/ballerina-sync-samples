import ballerina/log;

import bhashinee/dayforce;
import nuvindu/ldap;

configurable string adHostName = ?;
configurable int adPort = ?;
configurable string adDomainName = ?;
configurable string adPassword = ?;

configurable string adOU = "People";

final ldap:Client adClient = check new ({
    hostName: adHostName,
    port: adPort,
    domainName: adDomainName,
    password: adPassword
});

public function main() returns error? {
    map<record {}> users = map from dayforce:Employee employee in employees
        let string firstName = check employee.FirstName.ensureType(),
            string? lastName = employee.LastName
        select [
            getDistinguishedName(firstName, lastName),
            {
                "employeeID": employee.EmployeeNumber,
                "givenName": firstName,
                "sn": lastName,
                "displayName": lastName is () ? firstName : string `${firstName} ${lastName}`,
                "objectClass": "user",
                "userPrincipalName": string `${firstName.toLowerAscii()}${lastName is () ? "" : lastName.toLowerAscii()}@ad.windows`,
                "userAccountControl": "544"
            }
        ];

    foreach string dn in users.keys() {
        ldap:LDAPResponse|ldap:Error deleteRes = adClient->delete(dn);
        if deleteRes is error {
            log:printError("Failed to delete user", deleteRes, dn = dn);
        }
    }

    foreach var [dn, user] in users.entries() {
        ldap:LDAPResponse|ldap:Error addRes = adClient->add(dn, user);
        if addRes is error {
            log:printError("Failed to add user", addRes, dn = dn);
        }
    }
}

function getDistinguishedName(string firstName, string? lastName) returns string =>
    let string name = lastName is () ? firstName : string `${firstName} ${lastName}` in
        string `CN=${name},OU=${adOU},DC=ad,DC=windows`;
