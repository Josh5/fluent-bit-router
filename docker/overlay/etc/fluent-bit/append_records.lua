---[[
File: append_records.lua
Project: fluent-bit
Description: Inject host and environmental metadata into log records.
--]]

local env_name = os.getenv("ENVIRONMENT_NAME")
local env_region = os.getenv("ENVIRONMENT_REGION")
local instance_id = os.getenv("INSTANCE_ID")
local hostname = os.getenv("HOST_HOSTNAME") or os.getenv("HOSTNAME")
local env_project = os.getenv("ENVIRONMENT_PROJECT")

function append_records(tag, timestamp, record)
    local new_record = record

    new_record["source_tag"] = tag
    new_record["source_aggregator"] = "fluent-bit"

    if new_record["source_env"] == nil and env_name ~= nil and env_name ~= "" then
        new_record["source_env"] = env_name
    end
    if new_record["source_region"] == nil and env_region ~= nil and env_region ~= "" then
        new_record["source_region"] = env_region
    end
    if new_record["source_instance_id"] == nil and instance_id ~= nil and instance_id ~= "" then
        new_record["source_instance_id"] = instance_id
    end
    if new_record["source_hostname"] == nil and hostname ~= nil and hostname ~= "" then
        new_record["source_hostname"] = hostname
    end
    if new_record["source_project"] == nil and env_project ~= nil and env_project ~= "" then
        new_record["source_project"] = env_project
    end
    if new_record["source"] == nil then
        new_record["source"] = "node"
    end

    return 1, timestamp, new_record
end
