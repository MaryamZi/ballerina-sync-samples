import ballerina/ldap;
import ballerina/test;

import ballerinax/dayforce;

@test:Config {
    after: clearModifiedEmployeesArray
}
function testDayforceToMSADTransformation() returns error? {
    ADEmployee actual = check transform(employee1);
    ADEmployee expected = {
        employeeID: "67890",
        userPrincipalName: (),
        givenName: "Laura",
        middleName: "Jason",
        sn: "Timothy",
        displayName: "Laura Timothy",
        mobile: "0111111111",
        telephoneNumber: "0122222222",
        mail: "laura@test.com",
        title: "Data Worker",
        department: "Produce",
        company: "Grocery Co. AU",
        manager: "CN=Jason Jeffrey,OU=People,DC=ad,DC=windows",
        streetAddress: "45 Paradise Falls Road",
        st: "Victoria",
        co: "Australia",
        l: "Option1"
    };
    test:assertEquals(actual, expected);
}

@test:Config {
    after: clearModifiedEmployeesArray,
    dependsOn: [testDayforceToMSADTransformation]
}
function testSyncWithPagination() returns error? {
    check main();

    lock {
        test:assertEquals(modifiedEmployees.length(), 3);

        test:assertEquals(modifiedEmployees[0], check transform(employee1));
        test:assertEquals(modifiedEmployees[1], check transform(employee2));
        test:assertEquals(modifiedEmployees[2], check transform(employee3));
    }
}

isolated int dataRetrievalIteration = 1;

@test:Mock {
    functionName: "initDayforceClient"
}
function getMockDayforceClient() returns dayforce:Client|error =>
    test:mock(dayforce:Client, new MockDayforceClient());

// Mock Dayforce client with simplified paginated implementation.
isolated client class MockDayforceClient {
    resource isolated function post [string clientNamespace]/V1/EmployeeExportJobs(
            true isValidateOnly, dayforce:EmployeeExportParams payload) returns json|error {
        return {Data: {JobStatus: "Status/123456"}};
    }

    resource isolated function get [string clientNamespace]/v1/EmployeeExportJobs/Status/[int:Signed32 backgroundJobQueueItemId]() 
            returns dayforce:Payload_Object|error {
        return {
            Data: {
                [STATUS]: SUCCEEDED,
                "Results": "EmployeeExportJobs/Data/56789abc"
            }
        };
    }

    resource isolated function get [string clientNamespace]/v1/GetEmployeeBulkAPI/Data/[string jobId](dayforce:Paging? pagination = ()) 
            returns dayforce:PaginatedPayload_IEnumerable_Employee|error? {
        lock {
            if dataRetrievalIteration == 1 {
                dataRetrievalIteration = 2;
                return {
                    Data: [employee1, employee2],
                    Paging: {
                        Next: "http://localhost:8080/remainder"
                    }
                };
            }

            if dataRetrievalIteration == 2 {
                dataRetrievalIteration = 3;
                return {
                    Data: [employee3],
                    Paging: {
                        Next: ()
                    }
                };
            }

            return ();
        }
    }
}

isolated ADEmployee[] modifiedEmployees = [];

@test:Mock {
    functionName: "initLdapClient"
}
function getMockLdapClient() returns ldap:Client|error =>
    test:mock(ldap:Client, new MockLdapClient());

isolated client class MockLdapClient {
    remote isolated function modify(string distinguishedName, record {|anydata...;|} entry) 
            returns ldap:LdapResponse|ldap:Error {
        lock {
            ADEmployee adEmployee = <ADEmployee> entry.clone();
            modifiedEmployees.push(adEmployee);
        }
        return {resultCode: ldap:SUCCESS, operationType: "", matchedDN: ""};
    }
}

function clearModifiedEmployeesArray() {
    lock {
        modifiedEmployees.removeAll();
    }    
}

final dayforce:Employee & readonly employee1 = {
    "RequiresExitInterview": false,
    "BioExempt": false,
    "BirthDate": "1976-08-107T00:00:00",
    "ChecksumTimestamp": "2022-05-09T11:21:49.72",
    "ClockSupervisor": false,
    "Culture": {
        "XRefCode": "en-US",
        "ShortName": "English (US)",
        "LongName": "English (US)"
    },
    "EligibleForRehire": "NOTANSWERED",
    "FederatedId": "6789",
    "Gender": "F",
    "HireDate": "2002-01-01T00:00:00",
    "HomePhone": "5673450675",
    "NewHireApprovalDate": "2004-01-01T00:00:00",
    "NewHireApproved": true,
    "NewHireApprovedBy": "System",
    "OriginalHireDate": "2004-01-01T00:00:00",
    "PhotoExempt": false,
    "SeniorityDate": "2004-01-01T00:00:00",
    "SocialSecurityNumber": "12320137167678",
    "StartDate": "2004-01-01T00:00:00",
    "FirstTimeAccessEmailSentCount": 0,
    "FirstTimeAccessVerificationAttempts": 0,
    "SendFirstTimeAccessEmail": false,
    "EmployeeBadge": {
        "BadgeNumber": "67745066",
        "EffectiveStart": "2017-01-01T00:00:00",
        "LastModifiedTimestamp": "2017-06-20T15:33:57.203"
    },
    "LoginId": "kworker",
    "EmployeeNumber": "67890",
    "EmploymentStatuses": {
        "Items": [
            {
                "EmployeeNumber": "67890",
                "EffectiveStart": "2005-02-04T00:00:00",
                "EmploymentStatus": {
                    "IsBenefitArrearsEnabled": false,
                    "XRefCode": "ACTIVE",
                    "ShortName": "Active",
                    "LongName": "Active"
                },
                "EmploymentStatusGroup": {
                    "XRefCode": "ACTIVE",
                    "ShortName": "Active",
                    "LongName": "Active"
                },
                "PayType": {
                    "XRefCode": "HourlyNon",
                    "ShortName": "Hourly(Non-Exempt)",
                    "LongName": "Hourly(Non-Exempt)"
                },
                "PayGroup": {
                    "XRefCode": "AU",
                    "ShortName": "AU - Weekly",
                    "LongName": "AU - Weekly"
                },
                "PayTypeGroup": {
                    "XRefCode": "Hourly",
                    "ShortName": "Hourly",
                    "LongName": "Hourly"
                },
                "PayClass": {
                    "SortOrder": 10,
                    "DefaultNormalWeeklyHours": 40,
                    "LedgerCode": "FTLedgerCode1",
                    "XRefCode": "FT",
                    "ShortName": "FT",
                    "LongName": "Full Time"
                },
                "PunchPolicy": {
                    "XRefCode": "Default",
                    "ShortName": "Default",
                    "LongName": "Default"
                },
                "PayPolicy": {
                    "XRefCode": "GHourly",
                    "ShortName": "GHourly",
                    "LongName": "GHourly"
                },
                "PayHolidayGroup": {
                    "XRefCode": "AU",
                    "ShortName": "AU",
                    "LongName": "AU"
                },
                "EntitlementPolicy": {
                    "XRefCode": "Default",
                    "ShortName": "Default",
                    "LongName": "Default"
                },
                "ShiftRotation": {
                    "XRefCode": "Morning",
                    "ShortName": "Morning",
                    "LongName": "Morning"
                },
                "ShiftRotationDayOffset": 0,
                "ShiftRotationStartDate": "2007-12-31T00:00:00",
                "CreateShiftRotationShift": false,
                "TimeOffPolicy": {
                    "XRefCode": "Default",
                    "ShortName": "Default",
                    "LongName": "Default"
                },
                "ShiftTradePolicy": {
                    "XRefCode": "default",
                    "ShortName": "Corporate",
                    "LongName": "Corporate"
                },
                "AttendancePolicy": {
                    "XRefCode": "DEFAULT",
                    "ShortName": "Default",
                    "LongName": "Default"
                },
                "SchedulePolicy": {
                    "XRefCode": "Grocery",
                    "ShortName": "Grocery",
                    "LongName": "Grocery"
                },
                "OvertimeGroup": {
                    "XRefCode": "OTG1",
                    "ShortName": "OT Group 1",
                    "LongName": "OT Group 1"
                },
                "PayrollPolicy": {
                    "XRefCode": "AU",
                    "ShortName": "AU",
                    "LongName": "AU"
                },
                "AlternateRate": 3,
                "AverageDailyHours": 8,
                "BaseRate": 11.5,
                "BaseSalary": 23920,
                "NormalWeeklyHours": 40,
                "VacationRate": 10
            }
        ]
    },
    "WorkAssignments": {
        "Items": [
            {
                "Position": {
                    "Department": {
                        "XRefCode": "27",
                        "ShortName": "Produce",
                        "LongName": "Produce"
                    },
                    "Job": {
                        "EmployeeEEO": {
                            "XRefCode": "9",
                            "ShortName": "9 - Data Workers",
                            "LongName": "9 - Data Workers"
                        },
                        "IsUnionJob": false,
                        "JobClassification": {
                            "XRefCode": "SalesStaff",
                            "ShortName": "Sales and Service Staff",
                            "LongName": "Sales and Service Staff"
                        },
                        "FLSAStatus": {
                            "XRefCode": "NON-EXEMPT",
                            "ShortName": "Non-exempt",
                            "LongName": "Non-exempt"
                        },
                        "XRefCode": "312",
                        "ShortName": "Data Worker",
                        "LongName": "Data Worker"
                    },
                    "XRefCode": "Data Clerk",
                    "ShortName": "Data Clerk",
                    "LongName": "Data Clerk"
                },
                "Location": {
                    "ClockTransferCode": "654",
                    "LegalEntity": {
                        "Country": {
                            "Name": "Australia",
                            "XRefCode": "AU",
                            "ShortName": "Australia",
                            "LongName": "Australia"
                        },
                        "LegalEntityAddress": {
                            "Address1": "600 Van Ness Avenue",
                            "City": "Melbourne",
                            "PostalCode": "90210",
                            "Country": {
                                "Name": "Australia",
                                "XRefCode": "AU",
                                "ShortName": "Australia",
                                "LongName": "Australia"
                            },
                            "State": {
                                "Name": "Meloboune",
                                "XRefCode": "VI",
                                "ShortName": "Victoria"
                            }
                        },
                        "LegalIdNumber": "654556765983",
                        "XRefCode": "Grocery Co. AU",
                        "ShortName": "Grocery Co. AU",
                        "LongName": "Grocery Co. AU"
                    },
                    "XRefCode": "Store 32026",
                    "ShortName": "Store 320 - Produce"
                },
                "EffectiveStart": "2002-01-02T00:00:00",
                "IsPAPrimaryWorkSite": false,
                "IsPrimary": true,
                "IsStatutory": false,
                "IsVirtual": false,
                "LastModifiedTimeStamp": "2014-01-27T15:08:08.25"
            },
            {
                "Position": {
                    "Department": {
                        "XRefCode": "25",
                        "ShortName": "Snacks",
                        "LongName": "Snacks"
                    },
                    "Job": {
                        "EmployeeEEO": {
                            "XRefCode": "12",
                            "ShortName": "12 - Data Workers",
                            "LongName": "12 - Data Workers"
                        },
                        "IsUnionJob": false,
                        "JobClassification": {
                            "XRefCode": "SalesStaff",
                            "ShortName": "Sales and Service Staff",
                            "LongName": "Sales and Service Staff"
                        },
                        "FLSAStatus": {
                            "XRefCode": "NON-EXEMPT",
                            "ShortName": "Non-exempt",
                            "LongName": "Non-exempt"
                        },
                        "XRefCode": "31",
                        "ShortName": "Clerk",
                        "LongName": "Clerk"
                    },
                    "XRefCode": "Snacks Clerk",
                    "ShortName": "Snacks Clerk",
                    "LongName": "Snacks Clerk"
                },
                "Location": {
                    "ClockTransferCode": "653",
                    "LegalEntity": {
                        "Country": {
                            "Name": "Australia",
                            "XRefCode": "AU",
                            "ShortName": "Australia",
                            "LongName": "Australia"
                        },
                        "LegalEntityAddress": {
                            "Address1": "600 Van Ness Avenue",
                            "City": "Melbourne",
                            "PostalCode": "90210",
                            "Country": {
                                "Name": "Australia",
                                "XRefCode": "AU",
                                "ShortName": "Australia",
                                "LongName": "Australia"
                            },
                            "State": {
                                "Name": "Melbourne",
                                "XRefCode": "ME",
                                "ShortName": "Melbourne"
                            }
                        },
                        "LegalIdNumber": "65456455983",
                        "XRefCode": "Grocery Co. AU",
                        "ShortName": "Grocery Co. AU",
                        "LongName": "Grocery Co. AU"
                    },
                    "XRefCode": "Store 32025",
                    "ShortName": "Store 320 - Meat"
                },
                "EffectiveStart": "2014-01-05T00:00:00",
                "IsPAPrimaryWorkSite": false,
                "IsPrimary": false,
                "IsStatutory": false,
                "IsVirtual": false,
                "LastModifiedTimeStamp": "2014-01-30T14:10:16.537",
                "JobRate": 12
            }
        ]
    },
    "EmployeeManagers": {
        "Items": [
            {
                "EffectiveStart": "2013-01-05T00:00:00",
                "EffectiveEnd": "2020-01-05T00:00:00",
                "ManagerXRefCode": "78905",
                "ManagerFirstName": "Jason",
                "ManagerMiddleName": "Edward",
                "ManagerLastName": "Jeffrey",
                "ManagerBadgeNumber": "123455678"
            }
        ]
    },
    "Addresses": {
        "Items": [
            {
                "Address1": "45 Paradise Falls Road",
                "Address2": "29 Carolina Park Road",
                "Country": {
                    "Name": "Australia"
                },
                "State": {
                    "Name": "Victoria"
                }
            }
        ]
    },
    "EmployeeProperties": {
        "Items": [
            {
                "EffectiveEnd": "2020-01-05T00:00:00",
                "EffectiveStart": "2013-01-05T00:00:00",
                "EmployeeProperty": {
                    "ShortName": "Employee Work Address"
                },
                "OptionValue": {
                    "ShortName": "Option1"
                }
            }
        ]
    },
    "HomeOrganization": {
        "ContactCellPhone": "0111111111",
        "BusinessPhone": "0122222222",
        "ContactEmail": "laura@test.com",
        "ClockTransferCode": "654",
        "XRefCode": "Store2 320264",
        "ShortName": "Store2 3204 - Produce"
    },
    "Contacts": {
        "Items": [
            {
                "ContactInformationType": {
                    "XRefCode": "BusinessMobile"
                },
                "ContactNumber": "0111111111"
            },
            {
                "ContactInformationType": {
                    "XRefCode": "BusinessPhone"
                },
                "ContactNumber": "0122222222"
            },
            {
                "ContactInformationType": {
                    "XRefCode": "BusinessEmail"
                },
                "ContactNumber": "laura@test.com"
            }
        ]
    },
    "XRefCode": "67890",
    "CommonName": "Laura",
    "DisplayName": "Laura Timothy",
    "FirstName": "Laura",
    "LastName": "Timothy",
    "MiddleName": "Jason",
    "Initials": ""
};

final dayforce:Employee & readonly employee2 = {
    "RequiresExitInterview": false,
    "BioExempt": false,
    "BirthDate": "1990-09-217T00:00:00",
    "ChecksumTimestamp": "2023-05-33T11:21:49.72",
    "ClockSupervisor": false,
    "Culture": {
        "XRefCode": "en-US",
        "ShortName": "English (US)",
        "LongName": "English (US)"
    },
    "EligibleForRehire": "NOTANSWERED",
    "FederatedId": "6812",
    "Gender": "F",
    "HireDate": "2002-01-01T00:00:00",
    "HomePhone": "5673450675",
    "NewHireApprovalDate": "2004-01-01T00:00:00",
    "NewHireApproved": true,
    "NewHireApprovedBy": "System",
    "OriginalHireDate": "2004-01-01T00:00:00",
    "PhotoExempt": false,
    "SeniorityDate": "2004-01-01T00:00:00",
    "SocialSecurityNumber": "12320137167678",
    "StartDate": "2004-01-01T00:00:00",
    "FirstTimeAccessEmailSentCount": 0,
    "FirstTimeAccessVerificationAttempts": 0,
    "SendFirstTimeAccessEmail": false,
    "EmployeeBadge": {
        "BadgeNumber": "67745066",
        "EffectiveStart": "2017-01-01T00:00:00",
        "LastModifiedTimestamp": "2017-06-20T15:33:57.203"
    },
    "LoginId": "kworker",
    "EmployeeNumber": "67891",
    "EmploymentStatuses": {
        "Items": [
            {
                "EmployeeNumber": "67891",
                "EffectiveStart": "2005-02-04T00:00:00",
                "EmploymentStatus": {
                    "IsBenefitArrearsEnabled": false,
                    "XRefCode": "ACTIVE",
                    "ShortName": "Active",
                    "LongName": "Active"
                },
                "EmploymentStatusGroup": {
                    "XRefCode": "ACTIVE",
                    "ShortName": "Active",
                    "LongName": "Active"
                },
                "PayType": {
                    "XRefCode": "HourlyNon",
                    "ShortName": "Hourly(Non-Exempt)",
                    "LongName": "Hourly(Non-Exempt)"
                },
                "PayGroup": {
                    "XRefCode": "AU",
                    "ShortName": "AU - Weekly",
                    "LongName": "AU - Weekly"
                },
                "PayTypeGroup": {
                    "XRefCode": "Hourly",
                    "ShortName": "Hourly",
                    "LongName": "Hourly"
                },
                "PayClass": {
                    "SortOrder": 10,
                    "DefaultNormalWeeklyHours": 40,
                    "LedgerCode": "FTLedgerCode1",
                    "XRefCode": "FT",
                    "ShortName": "FT",
                    "LongName": "Full Time"
                },
                "PunchPolicy": {
                    "XRefCode": "Default",
                    "ShortName": "Default",
                    "LongName": "Default"
                },
                "PayPolicy": {
                    "XRefCode": "GHourly",
                    "ShortName": "GHourly",
                    "LongName": "GHourly"
                },
                "PayHolidayGroup": {
                    "XRefCode": "AU",
                    "ShortName": "AU",
                    "LongName": "AU"
                },
                "EntitlementPolicy": {
                    "XRefCode": "Default",
                    "ShortName": "Default",
                    "LongName": "Default"
                },
                "ShiftRotation": {
                    "XRefCode": "Morning",
                    "ShortName": "Morning",
                    "LongName": "Morning"
                },
                "ShiftRotationDayOffset": 0,
                "ShiftRotationStartDate": "2007-12-31T00:00:00",
                "CreateShiftRotationShift": false,
                "TimeOffPolicy": {
                    "XRefCode": "Default",
                    "ShortName": "Default",
                    "LongName": "Default"
                },
                "ShiftTradePolicy": {
                    "XRefCode": "default",
                    "ShortName": "Corporate",
                    "LongName": "Corporate"
                },
                "AttendancePolicy": {
                    "XRefCode": "DEFAULT",
                    "ShortName": "Default",
                    "LongName": "Default"
                },
                "SchedulePolicy": {
                    "XRefCode": "Grocery",
                    "ShortName": "Grocery",
                    "LongName": "Grocery"
                },
                "OvertimeGroup": {
                    "XRefCode": "OTG1",
                    "ShortName": "OT Group 1",
                    "LongName": "OT Group 1"
                },
                "PayrollPolicy": {
                    "XRefCode": "AU",
                    "ShortName": "AU",
                    "LongName": "AU"
                },
                "AlternateRate": 3,
                "AverageDailyHours": 8,
                "BaseRate": 11.5,
                "BaseSalary": 23920,
                "NormalWeeklyHours": 40,
                "VacationRate": 10
            }
        ]
    },
    "WorkAssignments": {
        "Items": [
            {
                "Position": {
                    "Department": {
                        "XRefCode": "27",
                        "ShortName": "Produce",
                        "LongName": "Produce"
                    },
                    "Job": {
                        "EmployeeEEO": {
                            "XRefCode": "9",
                            "ShortName": "9 - Data Workers",
                            "LongName": "9 - Data Workers"
                        },
                        "IsUnionJob": false,
                        "JobClassification": {
                            "XRefCode": "SalesStaff",
                            "ShortName": "Sales and Service Staff",
                            "LongName": "Sales and Service Staff"
                        },
                        "FLSAStatus": {
                            "XRefCode": "NON-EXEMPT",
                            "ShortName": "Non-exempt",
                            "LongName": "Non-exempt"
                        },
                        "XRefCode": "312",
                        "ShortName": "Data Worker",
                        "LongName": "Data Worker"
                    },
                    "XRefCode": "Data Clerk",
                    "ShortName": "Data Clerk",
                    "LongName": "Data Clerk"
                },
                "Location": {
                    "ClockTransferCode": "654",
                    "LegalEntity": {
                        "Country": {
                            "Name": "Australia",
                            "XRefCode": "AU",
                            "ShortName": "Australia",
                            "LongName": "Australia"
                        },
                        "LegalEntityAddress": {
                            "Address1": "600 Van Ness Avenue",
                            "City": "Melbourne",
                            "PostalCode": "90210",
                            "Country": {
                                "Name": "Australia",
                                "XRefCode": "AU",
                                "ShortName": "Australia",
                                "LongName": "Australia"
                            },
                            "State": {
                                "Name": "Meloboune",
                                "XRefCode": "VI",
                                "ShortName": "Victoria"
                            }
                        },
                        "LegalIdNumber": "654556765983",
                        "XRefCode": "Grocery Co. AU",
                        "ShortName": "Grocery Co. AU",
                        "LongName": "Grocery Co. AU"
                    },
                    "XRefCode": "Store 32026",
                    "ShortName": "Store 320 - Produce"
                },
                "EffectiveStart": "2002-01-02T00:00:00",
                "IsPAPrimaryWorkSite": false,
                "IsPrimary": true,
                "IsStatutory": false,
                "IsVirtual": false,
                "LastModifiedTimeStamp": "2014-01-27T15:08:08.25"
            },
            {
                "Position": {
                    "Department": {
                        "XRefCode": "25",
                        "ShortName": "Snacks",
                        "LongName": "Snacks"
                    },
                    "Job": {
                        "EmployeeEEO": {
                            "XRefCode": "12",
                            "ShortName": "12 - Data Workers",
                            "LongName": "12 - Data Workers"
                        },
                        "IsUnionJob": false,
                        "JobClassification": {
                            "XRefCode": "SalesStaff",
                            "ShortName": "Sales and Service Staff",
                            "LongName": "Sales and Service Staff"
                        },
                        "FLSAStatus": {
                            "XRefCode": "NON-EXEMPT",
                            "ShortName": "Non-exempt",
                            "LongName": "Non-exempt"
                        },
                        "XRefCode": "31",
                        "ShortName": "Clerk",
                        "LongName": "Clerk"
                    },
                    "XRefCode": "Snacks Clerk",
                    "ShortName": "Snacks Clerk",
                    "LongName": "Snacks Clerk"
                },
                "Location": {
                    "ClockTransferCode": "653",
                    "LegalEntity": {
                        "Country": {
                            "Name": "Australia",
                            "XRefCode": "AU",
                            "ShortName": "Australia",
                            "LongName": "Australia"
                        },
                        "LegalEntityAddress": {
                            "Address1": "600 Van Ness Avenue",
                            "City": "Melbourne",
                            "PostalCode": "90210",
                            "Country": {
                                "Name": "Australia",
                                "XRefCode": "AU",
                                "ShortName": "Australia",
                                "LongName": "Australia"
                            },
                            "State": {
                                "Name": "Melbourne",
                                "XRefCode": "ME",
                                "ShortName": "Melbourne"
                            }
                        },
                        "LegalIdNumber": "65456455983",
                        "XRefCode": "Grocery Co. AU",
                        "ShortName": "Grocery Co. AU",
                        "LongName": "Grocery Co. AU"
                    },
                    "XRefCode": "Store 32025",
                    "ShortName": "Store 320 - Meat"
                },
                "EffectiveStart": "2014-01-05T00:00:00",
                "IsPAPrimaryWorkSite": false,
                "IsPrimary": false,
                "IsStatutory": false,
                "IsVirtual": false,
                "LastModifiedTimeStamp": "2014-01-30T14:10:16.537",
                "JobRate": 12
            }
        ]
    },
    "EmployeeManagers": {
        "Items": [
            {
                "EffectiveStart": "2013-01-05T00:00:00",
                "EffectiveEnd": "2020-01-05T00:00:00",
                "ManagerXRefCode": "78905",
                "ManagerFirstName": "Jason",
                "ManagerMiddleName": "Edward",
                "ManagerLastName": "Jeffrey",
                "ManagerBadgeNumber": "123455678"
            }
        ]
    },
    "Addresses": {
        "Items": [
            {
                "Address1": "45 Paradise Falls Road",
                "Address2": "29 Carolina Park Road",
                "Country": {
                    "Name": "Australia"
                },
                "State": {
                    "Name": "Victoria"
                }
            }
        ]
    },
    "EmployeeProperties": {
        "Items": [
            {
                "EffectiveEnd": "2020-01-05T00:00:00",
                "EffectiveStart": "2013-01-05T00:00:00",
                "EmployeeProperty": {
                    "ShortName": "Employee Work Address"
                },
                "OptionValue": {
                    "ShortName": "Option1"
                }
            }
        ]
    },
    "HomeOrganization": {
        "ContactCellPhone": "0111111112",
        "BusinessPhone": "0122222223",
        "ContactEmail": "may@test.com",
        "ClockTransferCode": "654",
        "XRefCode": "Store2 320264",
        "ShortName": "Store2 3204 - Produce"
    },
    "Contacts": {
        "Items": [
            {
                "ContactInformationType": {
                    "XRefCode": "BusinessMobile"
                },
                "ContactNumber": "0111111112"
            },
            {
                "ContactInformationType": {
                    "XRefCode": "BusinessPhone"
                },
                "ContactNumber": "0122222223"
            },
            {
                "ContactInformationType": {
                    "XRefCode": "BusinessEmail"
                },
                "ContactNumber": "may@test.com"
            }
        ]
    },
    "XRefCode": "67891",
    "CommonName": "May",
    "DisplayName": "May William",
    "FirstName": "May",
    "LastName": "William",
    "MiddleName": "Anne",
    "Initials": ""
};

final dayforce:Employee & readonly employee3 = {
    "RequiresExitInterview": false,
    "BioExempt": false,
    "BirthDate": "1989-01-117T00:00:00",
    "ChecksumTimestamp": "2023-05-33T11:21:49.72",
    "ClockSupervisor": false,
    "Culture": {
        "XRefCode": "en-US",
        "ShortName": "English (US)",
        "LongName": "English (US)"
    },
    "EligibleForRehire": "NOTANSWERED",
    "FederatedId": "6813",
    "Gender": "F",
    "HireDate": "2002-01-01T00:00:00",
    "HomePhone": "5673450675",
    "NewHireApprovalDate": "2004-01-01T00:00:00",
    "NewHireApproved": true,
    "NewHireApprovedBy": "System",
    "OriginalHireDate": "2004-01-01T00:00:00",
    "PhotoExempt": false,
    "SeniorityDate": "2004-01-01T00:00:00",
    "SocialSecurityNumber": "12320137167678",
    "StartDate": "2004-01-01T00:00:00",
    "FirstTimeAccessEmailSentCount": 0,
    "FirstTimeAccessVerificationAttempts": 0,
    "SendFirstTimeAccessEmail": false,
    "EmployeeBadge": {
        "BadgeNumber": "67745066",
        "EffectiveStart": "2017-01-01T00:00:00",
        "LastModifiedTimestamp": "2017-06-20T15:33:57.203"
    },
    "LoginId": "kworker",
    "EmployeeNumber": "67892",
    "EmploymentStatuses": {
        "Items": [
            {
                "EmployeeNumber": "67892",
                "EffectiveStart": "2005-02-04T00:00:00",
                "EmploymentStatus": {
                    "IsBenefitArrearsEnabled": false,
                    "XRefCode": "ACTIVE",
                    "ShortName": "Active",
                    "LongName": "Active"
                },
                "EmploymentStatusGroup": {
                    "XRefCode": "ACTIVE",
                    "ShortName": "Active",
                    "LongName": "Active"
                },
                "PayType": {
                    "XRefCode": "HourlyNon",
                    "ShortName": "Hourly(Non-Exempt)",
                    "LongName": "Hourly(Non-Exempt)"
                },
                "PayGroup": {
                    "XRefCode": "AU",
                    "ShortName": "AU - Weekly",
                    "LongName": "AU - Weekly"
                },
                "PayTypeGroup": {
                    "XRefCode": "Hourly",
                    "ShortName": "Hourly",
                    "LongName": "Hourly"
                },
                "PayClass": {
                    "SortOrder": 10,
                    "DefaultNormalWeeklyHours": 40,
                    "LedgerCode": "FTLedgerCode1",
                    "XRefCode": "FT",
                    "ShortName": "FT",
                    "LongName": "Full Time"
                },
                "PunchPolicy": {
                    "XRefCode": "Default",
                    "ShortName": "Default",
                    "LongName": "Default"
                },
                "PayPolicy": {
                    "XRefCode": "GHourly",
                    "ShortName": "GHourly",
                    "LongName": "GHourly"
                },
                "PayHolidayGroup": {
                    "XRefCode": "AU",
                    "ShortName": "AU",
                    "LongName": "AU"
                },
                "EntitlementPolicy": {
                    "XRefCode": "Default",
                    "ShortName": "Default",
                    "LongName": "Default"
                },
                "ShiftRotation": {
                    "XRefCode": "Morning",
                    "ShortName": "Morning",
                    "LongName": "Morning"
                },
                "ShiftRotationDayOffset": 0,
                "ShiftRotationStartDate": "2007-12-31T00:00:00",
                "CreateShiftRotationShift": false,
                "TimeOffPolicy": {
                    "XRefCode": "Default",
                    "ShortName": "Default",
                    "LongName": "Default"
                },
                "ShiftTradePolicy": {
                    "XRefCode": "default",
                    "ShortName": "Corporate",
                    "LongName": "Corporate"
                },
                "AttendancePolicy": {
                    "XRefCode": "DEFAULT",
                    "ShortName": "Default",
                    "LongName": "Default"
                },
                "SchedulePolicy": {
                    "XRefCode": "Grocery",
                    "ShortName": "Grocery",
                    "LongName": "Grocery"
                },
                "OvertimeGroup": {
                    "XRefCode": "OTG1",
                    "ShortName": "OT Group 1",
                    "LongName": "OT Group 1"
                },
                "PayrollPolicy": {
                    "XRefCode": "AU",
                    "ShortName": "AU",
                    "LongName": "AU"
                },
                "AlternateRate": 3,
                "AverageDailyHours": 8,
                "BaseRate": 11.5,
                "BaseSalary": 23920,
                "NormalWeeklyHours": 40,
                "VacationRate": 10
            }
        ]
    },
    "WorkAssignments": {
        "Items": [
            {
                "Position": {
                    "Department": {
                        "XRefCode": "27",
                        "ShortName": "Produce",
                        "LongName": "Produce"
                    },
                    "Job": {
                        "EmployeeEEO": {
                            "XRefCode": "9",
                            "ShortName": "9 - Data Workers",
                            "LongName": "9 - Data Workers"
                        },
                        "IsUnionJob": false,
                        "JobClassification": {
                            "XRefCode": "SalesStaff",
                            "ShortName": "Sales and Service Staff",
                            "LongName": "Sales and Service Staff"
                        },
                        "FLSAStatus": {
                            "XRefCode": "NON-EXEMPT",
                            "ShortName": "Non-exempt",
                            "LongName": "Non-exempt"
                        },
                        "XRefCode": "312",
                        "ShortName": "Data Worker",
                        "LongName": "Data Worker"
                    },
                    "XRefCode": "Data Clerk",
                    "ShortName": "Data Clerk",
                    "LongName": "Data Clerk"
                },
                "Location": {
                    "ClockTransferCode": "654",
                    "LegalEntity": {
                        "Country": {
                            "Name": "Australia",
                            "XRefCode": "AU",
                            "ShortName": "Australia",
                            "LongName": "Australia"
                        },
                        "LegalEntityAddress": {
                            "Address1": "600 Van Ness Avenue",
                            "City": "Melbourne",
                            "PostalCode": "90210",
                            "Country": {
                                "Name": "Australia",
                                "XRefCode": "AU",
                                "ShortName": "Australia",
                                "LongName": "Australia"
                            },
                            "State": {
                                "Name": "Meloboune",
                                "XRefCode": "VI",
                                "ShortName": "Victoria"
                            }
                        },
                        "LegalIdNumber": "654556765983",
                        "XRefCode": "Grocery Co. AU",
                        "ShortName": "Grocery Co. AU",
                        "LongName": "Grocery Co. AU"
                    },
                    "XRefCode": "Store 32026",
                    "ShortName": "Store 320 - Produce"
                },
                "EffectiveStart": "2002-01-02T00:00:00",
                "IsPAPrimaryWorkSite": false,
                "IsPrimary": true,
                "IsStatutory": false,
                "IsVirtual": false,
                "LastModifiedTimeStamp": "2014-01-27T15:08:08.25"
            },
            {
                "Position": {
                    "Department": {
                        "XRefCode": "25",
                        "ShortName": "Snacks",
                        "LongName": "Snacks"
                    },
                    "Job": {
                        "EmployeeEEO": {
                            "XRefCode": "12",
                            "ShortName": "12 - Data Workers",
                            "LongName": "12 - Data Workers"
                        },
                        "IsUnionJob": false,
                        "JobClassification": {
                            "XRefCode": "SalesStaff",
                            "ShortName": "Sales and Service Staff",
                            "LongName": "Sales and Service Staff"
                        },
                        "FLSAStatus": {
                            "XRefCode": "NON-EXEMPT",
                            "ShortName": "Non-exempt",
                            "LongName": "Non-exempt"
                        },
                        "XRefCode": "31",
                        "ShortName": "Clerk",
                        "LongName": "Clerk"
                    },
                    "XRefCode": "Snacks Clerk",
                    "ShortName": "Snacks Clerk",
                    "LongName": "Snacks Clerk"
                },
                "Location": {
                    "ClockTransferCode": "653",
                    "LegalEntity": {
                        "Country": {
                            "Name": "Australia",
                            "XRefCode": "AU",
                            "ShortName": "Australia",
                            "LongName": "Australia"
                        },
                        "LegalEntityAddress": {
                            "Address1": "600 Van Ness Avenue",
                            "City": "Melbourne",
                            "PostalCode": "90210",
                            "Country": {
                                "Name": "Australia",
                                "XRefCode": "AU",
                                "ShortName": "Australia",
                                "LongName": "Australia"
                            },
                            "State": {
                                "Name": "Melbourne",
                                "XRefCode": "ME",
                                "ShortName": "Melbourne"
                            }
                        },
                        "LegalIdNumber": "65456455983",
                        "XRefCode": "Grocery Co. AU",
                        "ShortName": "Grocery Co. AU",
                        "LongName": "Grocery Co. AU"
                    },
                    "XRefCode": "Store 32025",
                    "ShortName": "Store 320 - Meat"
                },
                "EffectiveStart": "2014-01-05T00:00:00",
                "IsPAPrimaryWorkSite": false,
                "IsPrimary": false,
                "IsStatutory": false,
                "IsVirtual": false,
                "LastModifiedTimeStamp": "2014-01-30T14:10:16.537",
                "JobRate": 12
            }
        ]
    },
    "EmployeeManagers": {
        "Items": [
            {
                "EffectiveStart": "2013-01-05T00:00:00",
                "EffectiveEnd": "2020-01-05T00:00:00",
                "ManagerXRefCode": "78905",
                "ManagerFirstName": "Jason",
                "ManagerMiddleName": "Edward",
                "ManagerLastName": "Jeffrey",
                "ManagerBadgeNumber": "123455678"
            }
        ]
    },
    "Addresses": {
        "Items": [
            {
                "Address1": "45 Paradise Falls Road",
                "Address2": "29 Carolina Park Road",
                "Country": {
                    "Name": "Australia"
                },
                "State": {
                    "Name": "Victoria"
                }
            }
        ]
    },
    "EmployeeProperties": {
        "Items": [
            {
                "EffectiveEnd": "2020-01-05T00:00:00",
                "EffectiveStart": "2013-01-05T00:00:00",
                "EmployeeProperty": {
                    "ShortName": "Employee Work Address"
                },
                "OptionValue": {
                    "ShortName": "Option1"
                }
            }
        ]
    },
    "HomeOrganization": {
        "ContactCellPhone": "0111111113",
        "BusinessPhone": "0122222224",
        "ContactEmail": "sara@test.com",
        "ClockTransferCode": "654",
        "XRefCode": "Store2 320264",
        "ShortName": "Store2 3204 - Produce"
    },
    "Contacts": {
        "Items": [
            {
                "ContactInformationType": {
                    "XRefCode": "BusinessMobile"
                },
                "ContactNumber": "0111111113"
            },
            {
                "ContactInformationType": {
                    "XRefCode": "BusinessPhone"
                },
                "ContactNumber": "0122222224"
            },
            {
                "ContactInformationType": {
                    "XRefCode": "BusinessEmail"
                },
                "ContactNumber": "sara@test.com"
            }
        ]
    },
    "XRefCode": "67892",
    "CommonName": "Sara",
    "DisplayName": "Sara John",
    "FirstName": "Sara",
    "LastName": "John",
    "MiddleName": "",
    "Initials": ""
};
