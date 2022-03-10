local subsystem = ngx.config.subsystem
local load_pb = require("kong.plugins.opentelemetry.otlp").load_pb
local to_pb = require("kong.plugins.opentelemetry.otlp").to_pb
local to_otlp_span = require("kong.plugins.opentelemetry.otlp").to_otlp_span
local otlp_export_request = require("kong.plugins.opentelemetry.otlp").otlp_export_request
local new_tab = require "table.new"
local insert = table.insert
local ngx = ngx
local inspect = require "inspect"
local kong = kong


local OpenTelemetryHandler = {
  VERSION = "0.0.1",
  -- We want to run first so that timestamps taken are at start of the phase
  -- also so that other plugins might be able to use our structures
  PRIORITY = 100000,
}

-- cache exporter instances
local exporter_cache = setmetatable({}, { __mode = "k" })


function OpenTelemetryHandler:init_worker()
  assert(load_pb())
end


function OpenTelemetryHandler:access(conf)
  local span = kong.tracer:start_span(ngx.ctx, "access")
  span:set_attribute("route.name", "test")
  ngx.log(ngx.ERR, "--------------access")
end


function OpenTelemetryHandler:body_filter()
  if not ngx.arg[2] then
    return
  end

  local span = kong.tracer:get_current_span(ngx.ctx)
  if span ~= nil then
    ngx.log(ngx.ERR, "--------------end")
    span:finish()
  end
end


-- collect trace and spans
function OpenTelemetryHandler:log(conf) -- luacheck: ignore 212
  local spans = kong.tracer:spans_from_ctx()
  if spans == nil or #spans == 0 then
    ngx.log(ngx.NOTICE, "skip empty spans")
    return
  end

  local req = assert(otlp_export_request(spans))
  ngx.log(ngx.NOTICE, inspect(req))
end


return OpenTelemetryHandler
