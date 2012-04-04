--                                                                                                                                                                            --  Copyright 2012 Rackspace
--
--  Licensed under the Apache License, Version 2.0 (the "License");
--  you may not use this file except in compliance with the License.
--  You may obtain a copy of the License at
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software
--  distributed under the License is distributed on an "AS IS" BASIS,
--  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--  See the License for the specific language governing permissions and
--  limitations under the License.
--

module(..., package.seeall);
local io = require 'io'
local util = require 'util'
local Check = util.Check
local log = util.log

-- Munin to Cloudkick type mappings
local type_mappings = { counter = Check.enum.gauge, absolute = Check.enum.int64,
                        derive = Check.enum.gauge, gauge = Check.enum.int64,
                        default = Check.enum.int64 }

-- Default Munin metric type is gauge
local default_metric_type = type_mappings['default']

-- MUNIN_LIBDIR environment variable needs to be set, because many shell plugins
-- include a file with utility function located at MUNIN_LIBDIR/plugins/plugin.sh
-- Currently I just set this environment variable it to munin_plugins_path,
-- but that is far from ideal, because this means that the user must create a
-- plugins/ directory under the munin_plugins_path and copy the plugin.sh file
-- from the Munin distribution there...
local munin_libdir = ''

local function env_table_to_string(env_table)
  local env_string = ''

  for key, value in pairs(env_table) do
    env_string = string.format('%s %s="%s"', env_string, key, value)
  end

  return env_string
end

local function command(cmd, args, env, no_lf)
  local no_lf = no_lf or true
  local t, command

  t = assert(io.open(cmd))
  t:close()

  cmd = '"' .. cmd .. '"'
  if env then
    env = env_table_to_string(env)
    command = env .. ' ' .. cmd
  else
    command = cmd
  end

  if args then
    command = command .. ' ' .. args
  end

  command = command .. ' 2>&1; echo "-retcode:$?"'

  local f = io.popen(command ,'r')
  local l = f:read '*a'
  f:close()
  local i1,i2,ret = l:find('%-retcode:(%d+)\n$')
  if no_lf and i1 > 1 then i1 = i1 - 1 end
  l = l:sub(1,i1-1)
  return l,tonumber(ret)
end

local function parse_capabilities(plugin_path)
  -- Parse plugin capabilities.
  --
  -- Currently we only care about 'autoconf'
  local line, end_pos, value, capability
  local capabilities = {}
  local file = assert(io.open(plugin_path, 'r'))

  for line in file:lines() do
    _, end_pos = string.find(line, '#%%# capabilities=')

    if end_pos then
      value = string.sub(line, end_pos + 1)

      for _, capability in ipairs(util.split(value)) do
        capabilities[capability] = true
      end
    end
  end

  io.close(file)

  return capabilities
end

local function parse_threshold_values(value)
  -- Parse lower and upper bound from a threshold value.
  --
  -- Threshold value is in the following format:
  -- <min>:<max>
  local semicolon_pos, len
  local min, max = nil, nil

  if not value then
    return min, max
  end

  value = util.trim(value)

  semicolon_pos, _ = string.find(value, ':')

  if semicolon_pos == nil then
    -- Support old limits format - field.<warning/critical> <max>
    max = util.trim(value)
  else
    len = string.len(string.sub(value, semicolon_pos + 1))

    if semicolon_pos ~= 1 then
      min = string.sub(value, 1, semicolon_pos - 1)
    end

    if len ~= 0 then
      max = string.sub(value, semicolon_pos + 1)
    end
  end

  return min, max
end

local function parse_environment_variables(output, environment_variables)
  -- Parse environment variable directives from a string.
  --
  -- Environment variables are in the following format:
  -- env.<variable name> <variable value>
  local environment_variables = environment_variables or {}
  local env_name, env_value
  local end_post, whitespace_pos

  for _, line in ipairs(util.split(output, '[^\n]+')) do repeat
    if line == nil or not string.find(line, 'env.') then
      break
    end

    _, end_pos = string.find(line, 'env.')
    _, whitespace_pos = string.find(line, ' ', end_pos + 1)

    if not whitespace_pos then
      break
    end

    env_name, _ = string.sub(line, end_pos + 1, whitespace_pos)
    env_value, _ = string.sub(line, whitespace_pos + 1)

    if not env_name or not env_value then
      break
    end

    env_name, env_value = util.trim(util.remove_non_alphanum(env_name)),
                          util.trim(util.remove_non_alphanum(env_value))
    environment_variables[env_name] = env_value
  until true end

  return environment_variables
end

local function parse_directives(output, directives, directive_types,
                                parsed_directives)
  -- Parse directives specified in the directives table.
  --
  -- Directives can be in one of the following format:
  -- <directive> <value> (directive_type = 'graph')
  -- <field>.<directive> <value> (directive_type = 'field')
  local parsed_directives = parsed_directives or {}
  local pos_start, pos_end, metric_name, value

  for _, line in ipairs(util.split(output, '[^\n]+')) do
    for index, directive in ipairs(directives) do repeat
      if (directive_types[index] == 'graph') then
        pos_start, pos_end = string.find(line, directive .. ' ')
      else
        pos_start, pos_end = string.find(line, '%.' .. directive .. ' ')
      end

      if pos_start then
        value = string.sub(line, pos_end + 1)

        if (directive_types[index] == 'graph') then
          parsed_directives[directive] = value
        else
          metric_name = string.sub(line, 1, pos_start - 1)

          parsed_directives[directive] = {}
          parsed_directives[directive][metric_name] = value
        end
        break
      end
    until true end
  end

  return parsed_directives
end

local function postprocess_directives(directives)
  -- Posprocess the config directives.
  -- Currently it only parses the upper and lower bound value for the warning
  -- and critical directive.
  local postprocessed_directives = {}

  for directive, metrics in pairs(directives) do
    if directive == 'warning' or directive == 'critical' then
      for metric, value in pairs(metrics) do
        directives[directive][metric] = {}
        directives[directive][metric]['min'],
        directives[directive][metric]['max'] = parse_threshold_values(value)
      end
    elseif directive == 'type' then
      for metric, value in pairs(metrics) do
        value = util.trim(string.lower(value))
        directives[directive][metric] = type_mappings[value]
      end
    end
  end

  return directives
end

local function parse_and_posprocess_directives(output, directives,
                                               directive_types,
                                               parsed_directives)
  parsed_directives = parse_directives(output, directives, directive_types,
                                       parsed_directives)
  parsed_directives = postprocess_directives(parsed_directives)

  return parsed_directives
end

local function parse_plugin_output(stdout, rcheck, config_directives)
  -- Parse plugin output, add metrics and set the check state based on the
  -- defined warning and critical directives
  local line, min, max
  local metric, metric_display_name, value, metric_type, dot_pos

  -- local graph_display_name = config_directives['graph_title']
  local metric_labels = config_directives['label'] or {}
  local metric_types = config_directives['type'] or {}
  local warning_thresholds = config_directives['warning'] or {}
  local error_thresholds = config_directives['critical'] or {}
  local min_thresholds = config_directives['min'] or {}
  local max_thresholds = config_directives['max'] or {}

  for _, line in ipairs(util.split(stdout, '[^\n]+')) do repeat
    _, dot_pos = string.find(line, '%.')

    if not dot_pos then
      break
    end

    metric = string.sub(line, 1, dot_pos - 1)
    value = string.sub(line, dot_pos + 7)

    if metric == nil or value == nil then
      break
    end

    --if not table.contains(metric_labels, metric, 'key') then
    --  metric_display_name = ''
    --else
    --  metric_display_name = metric_labels[metric]
    --end

    value = tonumber(value)

    if not table.contains(metric_types, metric, 'key') then
      metric_type = default_metric_type
    else
      metric_type = metric_types[metric]
    end

    -- Set a display name
    -- if graph_display_name ~= nil then
    --  rcheck:set_display_name(graph_display_name)
    --end

    -- Add a metric
    rcheck:add_metric(metric, value, metric_type)

    -- warning/critical threshold comparison
    if table.contains(warning_thresholds, metric, 'key') then
      min = warning_thresholds[metric]['min']
      max = warning_thresholds[metric]['max']

      if min ~= nil then
        rcheck:pull_and_compare_error(metric, Check.op.LT, tonumber(min),
                                      'warning')
      end

    if max ~= nil then
        rcheck:pull_and_compare_error(metric, Check.op.GT, tonumber(max),
                                      'warning')
      end
    end

    if table.contains(error_thresholds, metric, 'key') then
      min = error_thresholds[metric]['min']
      max = error_thresholds[metric]['max']

      if min ~= nil then
        rcheck:pull_and_compare_error(metric, Check.op.LT, min, 'error')
      end

    if max ~= nil then
        rcheck:pull_and_compare_error(metric, Check.op.GT, max, 'error')
      end
    end

    -- .min/.max threhold comparion
    -- If the value is bellow / above the threshold, discard it.
    -- I know that this is odd, but value needs to be added to the check first
    -- so the warning/critical comparision can be done.
    if table.contains(min_thresholds, metric, 'key') then
      min = tonumber(min_thresholds[metric])

      if value < min then
        rcheck:remove_metric(metric)
      end
    end

    if table.contains(max_thresholds, metric, 'key') then
      max = tonumber(max_thresholds[metric])

      if value > max then
        rcheck:remove_metric(metric)
      end
    end
  until true end
end

local function run_munin_plugin(plugin_path, rcheck)
  -- Run a munin plugin
  local file, config_content, plugin_content
  local stdout, code, config_path

  local environment_variables = { MUNIN_LIBDIR = munin_libdir }
  local capabilities = {}
  local config_directives = {}

  -- 1. Check if this plugin is useful on this node
  capabilities = parse_capabilities(plugin_path)
  if capabilities['autoconf'] then
    stdout, code =  command(plugin_path, 'autoconf', environment_variables)

    if code ~= 0 then
      rcheck:set_error('Executing autoconf failed')
      return
    end

    if util.trim(stdout) ~= 'yes' then
      rcheck:set_error('autoconf reported no')
      return
    end
  end

  -- 2. Check if a config file exists and if does, parse the env variables,
  -- threshold directives and min/max directives
  config_path = plugin_path .. '.conf'
  if util.file_exists(config_path) then
    file = assert(io.open(config_path, 'r'))
    config_content = file:read('*a')
    file:close()

    environment_variables = parse_environment_variables(config_content,
                                                        environment_variables)
  end

  -- 3. Run config to retrieve plugin options
  stdout, code = command(plugin_path, 'config', environment_variables)

   if code ~= 0 then
      rcheck:set_error('Executing config failed')
      return
    end

  config_directives = parse_and_posprocess_directives(stdout,
          {'graph_title', 'label', 'type', 'warning', 'critical', 'min', 'max'},
          {'graph', 'field', 'field', 'field', 'field', 'field', 'field'},
          config_directives)

  if config_content then
    -- Directives from the config file must be parsed after the default
    -- directives provided by the plugin because they have precedence.
    config_directives = parse_and_posprocess_directives(config_content,
          {'graph_title', 'label', 'type', 'warning', 'critical', 'min', 'max'},
          {'graph', 'field', 'field', 'field', 'field', 'field', 'field'},
          config_directives)
  end

  -- 4. Run the plugin
  stdout, code = command(plugin_path, nil, environment_variables, true)

  if code ~= 0 then
    rcheck:set_error('Plugin returned error: %s', output)
  end

  -- 5. Parse the plugin and do rest of the magic
  parse_plugin_output(stdout, rcheck, config_directives)
end

local function is_wildcard_plugin(plugin_name)
  if string.find(plugin_name, '_') then
    return true
  end

  return false
end

local function is_valid_wildcard_plugin(plugin_name)
  -- Return true if a plugin is a valid (configured) wildcard plugin - the
  -- plugin name does not end with an underscore (_).
  local length = string.len(plugin_name)
  local pos, _ = string.find(plugin_name, '_')

  if pos == length then
    -- Wildcard plugin is not configured
    return false
  end

  return true
end

function run(rcheck, args)
  local filename
  local plugins_path, plugin_path

  plugins_path = conf.munin_plugins_path
  munin_libdir = string.sub(conf.munin_plugins_path, 1, -2)

  if not args.filename then
    rcheck:set_error('Missing required argument \'filename\'')
    return rcheck
  end

  filename = args.filename[1]
  plugin_path = plugins_path .. filename

  if equus.p_is_windows() == 1 then
    rcheck:set_error('Munin plugins are not supported on Windows.')
    return rcheck
  end

  if not util.file_exists(plugin_path) then
    rcheck:set_error('File %s does not exist', plugin_path)
    return rcheck
  end

  if is_wildcard_plugin(filename) then
    if not is_valid_wildcard_plugin(filename) then
      rcheck:set_error('Wildcard plugin is not configured properly.')
      return rcheck
    end
  end

  run_munin_plugin(plugin_path, rcheck)

  return rcheck
end
