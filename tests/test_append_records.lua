local environment = {
    ENVIRONMENT_NAME = "prod",
    ENVIRONMENT_TYPE = "homelab",
    ENVIRONMENT_REGION = "nz",
    ENVIRONMENT_PROJECT = "streamingtech",
    INSTANCE_ID = "node-01",
    HOST_HOSTNAME = "router-01",
}

local original_getenv = os.getenv
os.getenv = function(name)
    return environment[name]
end

dofile("docker/overlay/etc/fluent-bit/append_records.lua")
os.getenv = original_getenv

local result_code, result_timestamp, enriched = append_missing_local_source_metadata(
    "flb.self.node.log.systemd.router-01",
    12345,
    { message = "test" }
)

assert(result_code == 1)
assert(result_timestamp == 12345)
assert(enriched.source_env == "prod")
assert(enriched.source_type == "homelab")
assert(enriched.source_region == "nz")
assert(enriched.source_project == "streamingtech")
assert(enriched.source_instance_id == "node-01")
assert(enriched.source_hostname == "router-01")

local _, _, preserved = append_missing_local_source_metadata(
    "flb.self.node.log.systemd.router-01",
    12345,
    { source_type = "existing" }
)

assert(preserved.source_type == "existing")

print("append_records.lua tests passed")
