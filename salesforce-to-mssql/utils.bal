function validateNonEmptyString(string value) returns string|error =>
    value.trim().length() == 0 ? error("Expected a non-empty string") : value;

function getNonEmptyStringValue(string value) returns string? =>
    value.trim().length() == 0 ? () : value;

function parseNonEmptyStringAsIntValue(string value) returns int|error? =>
    value.trim().length() == 0 ? () : int:fromString(value);
