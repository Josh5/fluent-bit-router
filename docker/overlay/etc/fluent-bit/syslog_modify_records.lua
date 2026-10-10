-- Normalize remote syslog without attributing it to the receiving router host.
local environment_fields = {
    source_env = "ENVIRONMENT_NAME",
    source_env_type = "ENVIRONMENT_TYPE",
    source_env_region = "ENVIRONMENT_REGION",
    source_env_isolation_scope = "ENVIRONMENT_ISOLATION_SCOPE",
}

local function present(value)
    return value ~= nil and tostring(value) ~= "" and value ~= "-"
end

function syslog_modify_records(tag, timestamp, record)
    record.source = "syslog"
    record.source_category = "system"
    record.source_routing_tag = tag
    record.source_aggregator = "fluent-bit"
    record.service_name = present(record.ident) and record.ident or "syslog"
    if present(record.host) then
        record.source_hostname = record.host
    elseif present(record.syslog_source_address) then
        record.source_hostname = record.syslog_source_address
    end

    -- PRI encodes facility * 8 + severity; it is not a journal PRIORITY value.
    local pri = tonumber(record.pri)
    record.level = "info"
    if pri and pri >= 0 and pri <= 191 then
        local severity = pri % 8
        record.syslog_facility = math.floor(pri / 8)
        record.syslog_severity = severity
        if severity <= 3 then
            record.level = "error"
        elseif severity == 4 then
            record.level = "warn"
        elseif severity == 7 then
            record.level = "debug"
        end
    end

    -- Deployment metadata can be shared; receiver hostname/instance ID cannot.
    for field, variable in pairs(environment_fields) do
        local value = os.getenv(variable)
        if record[field] == nil and present(value) then
            record[field] = value
        end
    end
    return 2, timestamp, record
end
