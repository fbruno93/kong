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
local http = require "resty.http"


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
  span:set_attribute("node", kong.node.get_hostname())
  span:set_attribute("http.host", kong.request.get_host())
  span:set_attribute("http.version", kong.request.get_http_version())
  span:set_attribute("http.method", kong.request.get_method())
  span:set_attribute("http.path", kong.request.get_path())

  local route = kong.router.get_route()
  local service = kong.router.get_service()
  if route and service then
    span:set_attribute("route.name", route.name)
    span:set_attribute("service.name", service.name)    
  end
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


local function http_send_spans(premature, uri, spans)
  if premature then
    return
  end

  local req = assert(otlp_export_request(spans))
  ngx.log(ngx.NOTICE, inspect(req))

  local pb_data = assert(to_pb(req))

  local httpc = http.new()
  local res, err = httpc:request_uri("http://172.17.0.10:4318/v1/traces", {
    method = "POST",
    body = pb_data,
    headers = {
      ["Content-Type"] = "application/x-protobuf",
      -- ["Lightstep-Access-Token"] = "50wl2iOB2w3M4Db521IWxlyauiezBbvjNXcqHHTtOvZ/lhkaSwvxDm59LOJqjgCURgu8/ecUFSTo+0ypX07Elwy0z6t3YVbxd0o8fZyl",
    },
    ssl_verify = false,
  })
  if not res then
    ngx.log(ngx.ERR, "request failed: ", err)
    return
  end

  if res.status ~= 200 then
    ngx.log(ngx.ERR, "request failed: ", res.body)
  end

  ngx.log(ngx.NOTICE, "sent single trace, status: ", res.status)
end


-- collect trace and spans
function OpenTelemetryHandler:log(conf) -- luacheck: ignore 212
  local spans = kong.tracer:spans_from_ctx()
  if type(spans) ~= "table" or #spans == 0 then
    ngx.log(ngx.NOTICE, "skip empty spans")
    return
  end

  ngx.timer.at(0, http_send_spans, conf.http_endpoint, spans)
end


return OpenTelemetryHandler
