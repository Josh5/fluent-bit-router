local cjson = require "cjson"

local function existing_path(image_path, repository_path)
    local file = io.open(image_path, "r")
    if file then
        file:close()
        return image_path
    end
    return repository_path
end

local script = arg and arg[1] or existing_path(
    "/etc/fluent-bit/apply_standard_record_formatting.lua",
    "docker/overlay/etc/fluent-bit/apply_standard_record_formatting.lua"
)
dofile(script)

local function assert_timestamp(actual, seconds, nanoseconds)
    assert(type(actual) == "table")
    assert(actual.sec == seconds)
    assert(actual.nsec == nanoseconds)
end

local function format(record, timestamp, expected_timestamp)
    local input_timestamp = timestamp or { sec = 1700000000, nsec = 125000000 }
    local code, returned_timestamp, formatted = standard_record_formatting(
        "test.service",
        input_timestamp,
        record
    )
    assert(code == 1)
    local expected = expected_timestamp or input_timestamp
    assert_timestamp(returned_timestamp, expected.sec, expected.nsec)
    return formatted, returned_timestamp
end

local namespaced = format({
    payload = '{"user":"josh","action":"login"}',
    metadata = '{"region":"nz"}',
    log = '{"level":"info","message":"login succeeded"}'
})
assert(namespaced.message == "login succeeded")
assert(namespaced["payload.user"] == "josh")
assert(namespaced["payload.action"] == "login")
assert(namespaced["metadata.region"] == "nz")
assert(namespaced.user == nil)
assert(namespaced.region == nil)
assert(namespaced.level == 6)
assert(namespaced.levelname == "info")
assert(namespaced.source == nil)
assert(namespaced.service_name == "test.service")
assert(namespaced.timestamp == "2023-11-14T22:13:20.125000000Z")
assert(namespaced.timestamp_source == "fluent-bit")

local utc_timestamp, utc_event_timestamp = format({
    message = "utc",
    timestamp = "2024-01-02T03:04:05.123456789Z"
}, { sec = 1000, nsec = 0 }, { sec = 1704164645, nsec = 123456789 })
assert(utc_timestamp.timestamp == "2024-01-02T03:04:05.123456789Z")
assert(utc_timestamp.source_timestamp == "2024-01-02T03:04:05.123456789Z")
assert(utc_timestamp.timestamp_source == "application")
assert_timestamp(utc_event_timestamp, 1704164645, 123456789)

local offset_timestamp, offset_event_timestamp = format({
    message = "offset",
    timestamp = "2024-01-02T16:04:05+13:00"
}, { sec = 1000, nsec = 0 }, { sec = 1704164645, nsec = 0 })
assert(offset_timestamp.timestamp == "2024-01-02T03:04:05.000000000Z")
assert(offset_timestamp.source_timestamp == "2024-01-02T16:04:05+13:00")
assert_timestamp(offset_event_timestamp, 1704164645, 0)

local envelope_timestamp, envelope_event_timestamp = format({
    log = '{"message":"delayed","timestamp":"2024-01-02T03:04:05Z"}'
}, { sec = 2000, nsec = 0 }, { sec = 1704164645, nsec = 0 })
assert(envelope_timestamp.timestamp == "2024-01-02T03:04:05.000000000Z")
assert(envelope_timestamp.source_timestamp == "2024-01-02T03:04:05Z")
assert_timestamp(envelope_event_timestamp, 1704164645, 0)

local root_timestamp, root_event_timestamp = format({
    timestamp = 1704164645,
    log = '{"message":"root wins","timestamp":"2025-01-02T03:04:05Z"}'
}, { sec = 2000, nsec = 0 }, { sec = 1704164645, nsec = 0 })
assert(root_timestamp.timestamp == "2024-01-02T03:04:05.000000000Z")
assert(root_timestamp.source_timestamp == 1704164645)
assert(root_timestamp.timestamp_extracted == "2025-01-02T03:04:05Z")
assert_timestamp(root_event_timestamp, 1704164645, 0)

local invalid_timestamp = format({
    message = "fallback",
    timestamp = "not-a-time"
}, { sec = 1234, nsec = 567 })
assert(invalid_timestamp.timestamp == "1970-01-01T00:20:34.000000567Z")
assert(invalid_timestamp.source_timestamp == "not-a-time")
assert(invalid_timestamp.timestamp_invalid == "not-a-time")
assert(invalid_timestamp.timestamp_source == "fluent-bit")

local epoch_scales = {
    { "1722762000.123456789", 1722762000, 123456789 },
    { "1722762000123",        1722762000, 123000000 },
    { "1722762000123456",     1722762000, 123456000 },
    { "1722762000123456789",  1722762000, 123456789 },
    { 1722762000123,          1722762000, 123000000 },
    { 1722762000123456,       1722762000, 123456000 }
}
for _, epoch_case in ipairs(epoch_scales) do
    local result, event_timestamp = format({
        message = "scaled epoch",
        timestamp = epoch_case[1]
    }, { sec = 1, nsec = 0 }, { sec = epoch_case[2], nsec = epoch_case[3] })
    assert(result.source_timestamp == epoch_case[1])
    assert(type(result.timestamp) == "string")
    assert_timestamp(event_timestamp, epoch_case[2], epoch_case[3])
end

local timestamp_table = { sec = 1722762000, nsec = 123456789 }
local table_timestamp_record, table_event_timestamp = format({
    message = "table timestamp",
    timestamp = timestamp_table
}, { sec = 1, nsec = 0 }, timestamp_table)
assert(table_timestamp_record.timestamp == "2024-08-04T09:00:00.123456789Z")
assert(table_timestamp_record.source_timestamp == timestamp_table)
assert(table_timestamp_record["timestamp.sec"] == nil)
assert(table_timestamp_record["timestamp.nsec"] == nil)
assert_timestamp(table_event_timestamp, 1722762000, 123456789)

local envelope_timestamp_table = { sec = 1722762000, nsec = 987654321 }
local envelope_table_record, envelope_table_event = format({
    log = {
        message = "envelope table timestamp",
        timestamp = envelope_timestamp_table
    }
}, { sec = 1, nsec = 0 }, envelope_timestamp_table)
assert(envelope_table_record.timestamp == "2024-08-04T09:00:00.987654321Z")
assert(envelope_table_record.source_timestamp == envelope_timestamp_table)
assert(envelope_table_record["timestamp.sec"] == nil)
assert_timestamp(envelope_table_event, 1722762000, 987654321)

local nested = format({
    levelname = "WARNING",
    request = {
        level = "err",
        method = "GET",
        headers = { "application/json", "gzip" }
    },
    log = '{"level":"debug","message":"handled"}'
})
assert(nested.level == 4)
assert(nested.levelname == "warn")
assert(nested["request.level"] == "err")
assert(nested["request.method"] == "GET")
assert(nested["request.headers.1"] == "application/json")
assert(nested["request.headers.2"] == "gzip")
assert(nested.level_extracted == "debug")

local collisions = format({
    message = "original",
    user = "root",
    log = '{"message":"from log","user":"log"}',
    msg = '{"message":"from msg","user":"msg"}'
})
assert(collisions.message == "original")
assert(collisions.message_extracted == "from log")
assert(collisions.message_extracted2 == "from msg")
assert(collisions.user == "root")
assert(collisions.user_extracted == "log")
assert(collisions.user_extracted2 == "msg")

local nulls = format({
    message = cjson.null,
    log = "null",
    payload = '{"empty":null,"present":"yes"}',
    metadata = "null"
})
assert(nulls.message == "NO MESSAGE")
assert(nulls["payload.empty"] == nil)
assert(nulls["payload.present"] == "yes")
assert(nulls.metadata == nil)

local deterministic = format({
    message = '{"z":1,"a":2,"nested":{"y":3,"b":4}}'
})
assert(deterministic.message == "a=2 nested.b=4 nested.y=3 z=1")

local nested_envelope_alias = format({
    log = '{"msg":"nested message"}'
})
assert(nested_envelope_alias.message == "nested message")

local boolean_message = format({ message = false })
assert(boolean_message.message == "false")

local empty_collections = format({
    message = "empty collections",
    request = {
        headers = {},
        labels = {}
    }
})
assert(empty_collections["request.headers"] == "{}")
assert(empty_collections["request.labels"] == "{}")

assert(type(cjson.decode_array_with_array_mt) == "function")
local decoded_empty_collections = format({
    message = "decoded empty collections",
    payload = '{"empty_array":[],"empty_object":{}}'
})
assert(decoded_empty_collections["payload.empty_array"] == "[]")
assert(decoded_empty_collections["payload.empty_object"] == "{}")

local fluent_bit_empty_collections = format({
    message = "Fluent Bit empty collections",
    native_array = setmetatable({}, { type = 1 }),
    native_object = setmetatable({}, { type = 2 })
})
assert(fluent_bit_empty_collections.native_array == "[]")
assert(fluent_bit_empty_collections.native_object == "{}")

local sparse = format({
    message = "sparse",
    values = { [1] = "a", [3] = "c" }
})
assert(sparse["values.1"] == "a")
assert(sparse["values.3"] == "c")

local identical_tables = format({
    message = "tables",
    empty = {},
    log = '{"empty":{}}'
})
assert(identical_tables.empty == "{}")
assert(identical_tables.empty_extracted == nil)

local empty_logfmt = format({
    message = { z = 1, empty = {} }
})
assert(empty_logfmt.message == 'empty="{}" z=1')

local mixed_keys = format({
    message = {
        [1] = "numeric",
        ["1"] = "string"
    }
})
assert(mixed_keys.message == "1=numeric 1=string")
assert((mixed_keys["1"] == "numeric" and mixed_keys["1_extracted"] == "string") or
    (mixed_keys["1"] == "string" and mixed_keys["1_extracted"] == "numeric"))

for alias, expected in pairs({
    err = { 3, "error" },
    warning = { 4, "warn" },
    emerg = { 0, "fatal" }
}) do
    local result = format({ message = "test", level = alias })
    assert(result.level == expected[1])
    assert(result.levelname == expected[2])
end

local recursively_decoded = format({
    message = '{"message":"{\\"level\\":\\"error\\",\\"message\\":\\"database failed\\"}"}'
})
assert(recursively_decoded.message == "database failed")
assert(recursively_decoded.level == 3)
assert(recursively_decoded.levelname == "error")

assert(format({ message = '"hello"' }).message == "hello")
assert(format({ message = "123" }).message == "123")
assert(format({ message = "true" }).message == "true")

local epoch_zero, epoch_zero_event = format({
    message = "epoch",
    timestamp = "1970-01-01T00:00:00Z"
}, { sec = 10, nsec = 0 }, { sec = 0, nsec = 0 })
assert(epoch_zero.timestamp == "1970-01-01T00:00:00.000000000Z")
assert_timestamp(epoch_zero_event, 0, 0)

local invalid_rfc3339_values = {
    "2024-01-02 03:04:05Z",
    "2024-01-02T03:04:60Z",
    "2024-01-02T03:04:05+15:00",
    "2024-01-02T03:04:05.1234567890Z"
}
for _, invalid_value in ipairs(invalid_rfc3339_values) do
    local result = format({ message = "invalid", timestamp = invalid_value },
        { sec = 10, nsec = 0 })
    assert(result.timestamp == "1970-01-01T00:00:10.000000000Z")
    assert(result.timestamp_invalid == invalid_value)
end

local eleven_digit_epoch, eleven_digit_event = format({
    message = "future",
    timestamp = "10000000000"
}, { sec = 10, nsec = 0 }, { sec = 10000000000, nsec = 0 })
assert(eleven_digit_epoch.source_timestamp == "10000000000")
assert_timestamp(eleven_digit_event, 10000000000, 0)

local pino = format({ message = "pino", level = 30 })
assert(pino.level == 30)
assert(pino.levelname == nil)

local named_over_numeric = format({ message = "named", level = 30, levelname = "warning" })
assert(named_over_numeric.level == 4)
assert(named_over_numeric.levelname == "warn")
assert(named_over_numeric.level_extracted == 30)

local loki_severity = format({ message = "severity", SeverityText = "alert" })
assert(loki_severity.level == 1)
assert(loki_severity.levelname == "critical")

local deep = { value = "end" }
for _ = 1, 70 do
    deep = { nested = deep }
end
local limited = format({ message = "limited", context = deep })
assert(limited.formatting_error:match("max_nesting_depth"))

local nested_json = '"final"'
for _ = 1, 7 do
    nested_json = cjson.encode({ message = nested_json })
end
local envelope_limited = format({ message = nested_json })
assert(envelope_limited.formatting_error:match("max_envelope_depth"))

local generated_limited = format({
    message = { data = string.rep("x", 9000) }
})
assert(#generated_limited.message <= 8192)
assert(generated_limited.formatting_error:match("generated_message_truncated"))

local wide = {}
for index = 1, 2050 do
    wide["field" .. index] = index
end
local fields_limited = format({ message = "wide", context = wide })
assert(fields_limited.formatting_error:match("max_flattened_fields"))

dofile(existing_path(
    "/etc/fluent-bit/traefik_modify_records.lua",
    "docker/overlay/etc/fluent-bit/traefik_modify_records.lua"
))
local traefik_input = {
    source_service = "traefik",
    message =
    [[{"ClientAddr":"192.0.2.10:4321","ClientHost":"192.0.2.10","RequestMethod":"GET","RequestAddr":"example.test","RequestPath":"/health","DownstreamStatus":404,"OriginStatus":404,"ServiceAddr":"10.0.0.2:8080","Duration":1234,"RouterName":"health@docker","ServiceName":"health-service@docker","Headers":[],"Metadata":{}}]]
}
local _, traefik_timestamp, traefik_record = traefik_modify_records(
    "traefik.test",
    { sec = 1700000000, nsec = 0 },
    traefik_input
)
assert_timestamp(traefik_timestamp, 1700000000, 0)
assert(traefik_record.Headers == "[]")
assert(traefik_record.Metadata == "{}")
assert(traefik_record.DownstreamStatus == 404)
assert(traefik_record.source_client_ip == "192.0.2.10")
assert(traefik_record.source_http_method == "GET")
assert(traefik_record.source_http_path == "/health")
assert(traefik_record.source_http_status == 404)
assert(traefik_record.source_request_duration == 1234)
assert(traefik_record.source_proxy_router == "health@docker")
assert(traefik_record.source_proxy_service == "health-service@docker")
assert(traefik_record.message ==
    "Status:404 Client From 192.0.2.10 GET example.test/health Route To 10.0.0.2:8080")

local formatted_traefik = format(traefik_record)
assert(formatted_traefik.Headers == "[]")
assert(formatted_traefik.Metadata == "{}")
assert(formatted_traefik.DownstreamStatus == 404)
assert(formatted_traefik.level == 4)
assert(formatted_traefik.levelname == "warn")
assert(formatted_traefik.message ==
    "Status:404 Client From 192.0.2.10 GET example.test/health Route To 10.0.0.2:8080")

local unrelated_record = {
    source_service = "traefik-watchdog",
    message = [[{"DownstreamStatus":500}]]
}
local unrelated_code, _, unrelated_result = traefik_modify_records(
    "docker.traefik-watchdog",
    { sec = 1700000000, nsec = 0 },
    unrelated_record
)
assert(unrelated_code == 0)
assert(unrelated_result == unrelated_record)
assert(unrelated_result.source_category == nil)

dofile(existing_path(
    "/etc/fluent-bit/systemd_modify_records.lua",
    "docker/overlay/etc/fluent-bit/systemd_modify_records.lua"
))
local system_log_code, _, system_log_record = system_log_add_unit(
    "node.log.system.test",
    { sec = 1700000000, nsec = 0 },
    { process = "sshd[1234]", message = "accepted connection" }
)
assert(system_log_code == 2)
assert(system_log_record.SYSTEMD_UNIT == "sshd.service")

dofile(existing_path(
    "/etc/fluent-bit/docker_modify_records.lua",
    "docker/overlay/etc/fluent-bit/docker_modify_records.lua"
))
local docker_input_timestamp = { sec = 1, nsec = 2 }
local docker_source_timestamp = "2026-08-04T08:00:00.123456789Z"
local _, docker_returned_timestamp, docker_record = docker_modify_records(
    "docker.test",
    docker_input_timestamp,
    {
        time = docker_source_timestamp,
        log = "docker message",
        attrs = {
            source_env = "test",
            source_service = "traefik",
            ["source.project"] = "router-tests"
        },
        labels = setmetatable({}, { type = 1 })
    }
)
assert(docker_returned_timestamp == docker_input_timestamp)
assert(docker_record.timestamp == docker_source_timestamp)
local formatted_docker, docker_event_timestamp = format(
    docker_record,
    docker_returned_timestamp,
    { sec = 1785830400, nsec = 123456789 }
)
assert(formatted_docker.message == "docker message")
assert(formatted_docker.labels == "[]")
assert(formatted_docker.source == "docker")
assert(formatted_docker.source_env == "test")
assert(formatted_docker.source_service == "traefik")
assert(formatted_docker.source_project == "router-tests")
assert(formatted_docker.source_timestamp == docker_source_timestamp)
assert_timestamp(docker_event_timestamp, 1785830400, 123456789)

dofile(existing_path(
    "/etc/fluent-bit/apply_graylog_formatting.lua",
    "docker/overlay/etc/fluent-bit/apply_graylog_formatting.lua"
))
local exact_timestamp = "2026-08-04T08:00:00.123456789Z"
local graylog_event_timestamp = { sec = 1785830400, nsec = 123456789 }
local _, returned_graylog_timestamp, graylog_record = graylog_formatting(
    "graylog.test",
    graylog_event_timestamp,
    { message = "graylog", timestamp = exact_timestamp }
)
assert(returned_graylog_timestamp == graylog_event_timestamp)
assert(graylog_record.timestamp == exact_timestamp)
assert(math.abs(graylog_record._gelf_timestamp - 1785830400.1234567) < 0.000001)

print("apply_standard_record_formatting.lua tests passed")

function formatting_test_callback(tag, timestamp, record)
    return 1, timestamp, record
end
